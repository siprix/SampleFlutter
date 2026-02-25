import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:siprix_voip_sdk/accounts_model.dart';
import 'simple_model.dart';

/////////////////////////////////////////////////////////////////////
///main

void main() {
  SipProvider sipProvider = SipProvider();

  runApp(
    MultiProvider(providers:[
      ChangeNotifierProvider(create: (context) => sipProvider),
    ],
    child: const MyApp(),
  ));
}

/////////////////////////////////////////////////////////////////////
///MyApp

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: <String, WidgetBuilder>{
        AccountPage.routeName: (BuildContext context) => const AccountPage(),
        HomePage.routeName: (BuildContext context) => const HomePage(),
      },
      title: 'Siprix Demo',
      home: const AccountPage(),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
    );
  }
}

enum AccAction {delete, unregister, register}

/////////////////////////////////////////////////////////////////////
///HomePage

class HomePage extends StatefulWidget {
  static const routeName = '/home';
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _phoneNumbCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child:_buildBody()));
  }

  void _onMakeCall() {
    context.read<SipProvider>().makeCall(_phoneNumbCtrl.text);
  }

  void _onEndCall() {
    context.read<SipProvider>().endCall()
      .catchError(showSnackBar);
  }

  void _onAcceptCall() {
    context.read<SipProvider>().answerCall()
      .catchError(showSnackBar);
  }

  void _onRejectCall() {
    context.read<SipProvider>().rejectCall()
      .catchError(showSnackBar);
  }

  void _onMuteMicCall() {
    context.read<SipProvider>().toggleMute()
      .catchError(showSnackBar);
  }

  Widget _buildBody() {
    final sipProvider = context.watch<SipProvider>();
    bool hasCall = sipProvider.currentCall!=null;
    bool isCallConnected = sipProvider.currentCall?.isConnected ?? false;
    bool isIncomingCall = sipProvider.currentCall?.isIncoming ?? false;

    return Column(children: [
      _buildAccSection(sipProvider),

      const Divider(height: 1),

      Wrap(spacing: 5, crossAxisAlignment: WrapCrossAlignment.center, children:[
        SizedBox(width: 120, child:
          TextFormField(controller: _phoneNumbCtrl,
            enabled: !hasCall,
            decoration: const InputDecoration(hintText: 'Phone number',isDense: true)
          )
        ),

        TextButton(onPressed: hasCall ? null : _onMakeCall,
          child: const Text("MakeCall")),
      ]),

      if(hasCall)
        Text(sipProvider.callStatus),

      if(isCallConnected) ...[
        Text("Call duration: ${sipProvider.formattedDuration}"),

        if(isCallConnected)
          TextButton(onPressed: _onMuteMicCall, child: Text(sipProvider.isMuted ? "Unmute mic":"Mute mic") ),
      ],

      if((hasCall && !isIncomingCall) || isCallConnected)
        TextButton(onPressed: _onEndCall, child: Text(isCallConnected ? "EndCall" : "CancelCall")),

      if(isIncomingCall && !isCallConnected)
        Row(spacing: 15, mainAxisAlignment: MainAxisAlignment.center, children:[
          TextButton(onPressed: _onAcceptCall, child: const Text("Accept")),
          TextButton(onPressed: _onRejectCall, child: const Text("Reject")),
        ]),
    ]);
  }

  Widget _buildAccSection(SipProvider sipProvider) {
    String regState = sipProvider.accountStatus;
    return ListTile(
        leading: _getAccIcon(sipProvider.accountRegState),
        title: Text(sipProvider.accountUri, style: Theme.of(context).textTheme.titleSmall, overflow: TextOverflow.ellipsis),
        subtitle: Text(regState, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.0, fontStyle: FontStyle.italic, color: Colors.grey)),
        trailing: _accListTileMenu(sipProvider),
        dense: true,
      );
  }

  Widget _getAccIcon(RegState s) {
    switch(s){
      case RegState.success:    return const Icon(Icons.cloud_done_outlined, color: Colors.green);
      case RegState.failed:     return const Icon(Icons.cloud_off_outlined, color: Colors.red);
      case RegState.inProgress: return const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 3,));
      default:                  return const Icon(Icons.done, color: Colors.grey);
    }
  }

  PopupMenuButton<AccAction> _accListTileMenu(SipProvider sipProvider) {
    RegState regState = sipProvider.accountRegState!;
    return
      PopupMenuButton<AccAction>(
        onSelected: _doAccountAction,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<AccAction>>[
          PopupMenuItem<AccAction>(
            value: AccAction.register,
            enabled: (regState!=RegState.inProgress),
            child: const Wrap(spacing:5, children:[Icon(Icons.refresh), Text("Register"),])
          ),
          PopupMenuItem<AccAction>(
            value: AccAction.unregister,
            enabled: (regState!=RegState.inProgress)&&(regState!=RegState.removed),
            child: const Wrap(spacing:5, children:[Icon(Icons.cancel_presentation), Text("Unregister")])
          ),
          const PopupMenuDivider(),
          const PopupMenuItem<AccAction>(
            value: AccAction.delete,
            child: Wrap(spacing:5, children:[Icon(Icons.logout), Text("Logout"),])
          ),
        ],
      );
  }

  void _doAccountAction(AccAction action) {
    final sipProvider = context.read<SipProvider>();
    Future<void> f;
    switch(action) {
      case AccAction.delete:     f = sipProvider.deleteAccount();  break;
      case AccAction.unregister: f = sipProvider.unregister(); break;
      case AccAction.register:   f = sipProvider.refreshRegistration(); break;
    }
    f.catchError(showSnackBar);
  }

  void showSnackBar(dynamic err) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }
}

/////////////////////////////////////////////////////////////////////
///AccountPage

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  static const routeName = '/addAccount';

  @override
  AccountPageState createState() => AccountPageState();
}

class AccountPageState extends State<AccountPage> {
  final _passwordVisibleNotifier = ValueNotifier<bool>(false);
  final _formKey = GlobalKey<FormState>();
  final AccountModel _account = AccountModel();
  bool _isRegistering = true;
  String _errText = "";

  @override
  void initState() {
    super.initState();
    _initAndLoadSavedAccount();
  }

  void _initAndLoadSavedAccount() async {
    //Init
    final sipProvider = context.read<SipProvider>();
    sipProvider.initializeSiprix();

    //Set reg callback
    sipProvider.accRegStateChanged = _handleAccRegState;
    sipProvider.accDeleted = _handleAccDeleted;

    //Load saved account
    bool loaded = await sipProvider.loadSavedAccount();

    //Stop progress indicator if account not loaded
    if(!loaded) setState(() { _isRegistering=false; });
  }


  void _handleAccRegState(RegState state, String response) {
    if(state == RegState.success) {
      //Registration success - remove callback and go to home screen
      context.read<SipProvider>().accRegStateChanged = null;
      Navigator.of(context).pushNamed(HomePage.routeName);
      setState(() { _errText=""; _isRegistering=false; });
    } else if(state == RegState.failed) {
      //Registration failed - display error text
      setState(() { _errText = response; _isRegistering=false; });
    }
  }

  void _handleAccDeleted() {
    Navigator.of(context).pop();
    context.read<SipProvider>().accRegStateChanged = _handleAccRegState;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body:
      Form(key: _formKey, child:
        Padding(padding: const EdgeInsets.fromLTRB(10, 5, 10, 10), child:
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Spacer(),
            if(_isRegistering)  Center(child:CircularProgressIndicator(strokeWidth: 3)),
            _buildSipServer(),
            _buildSipExtension(),
            _buildPassword(),
            Text(_errText, style: const TextStyle(color: Colors.red)),
            _buildSubmitButton(),
          ])
        )
    ));
  }

  Widget _buildSubmitButton() {
    return
      Padding(padding: const EdgeInsets.all(20),
        child: ElevatedButton(onPressed: _isRegistering ? null : _submit,
          child: Wrap(spacing:5,
            children: [const Icon(Icons.archive), Text('Register')
          ])
        )
      );
  }

  Widget _buildSipServer() {
    return  TextFormField(
      decoration: const InputDecoration(labelText: 'Sip server/domain'),
       validator: (value) { return (value == null || value.isEmpty) ? 'Please enter domain' : null; },
       onChanged: (String? value) { setState(() { if((value!=null) && value.isNotEmpty) _account.sipServer = value; }); },
    );
  }

  Widget _buildSipExtension() {
    return TextFormField(
        decoration: const InputDecoration(labelText: 'Sip extension'),
        validator: (value) { return (value == null || value.isEmpty) ? 'Please enter user name.' : null; },
        onChanged: (String? value) { setState(() { if((value!=null) && value.isNotEmpty) _account.sipExtension = value; }); },
      );
  }

  Widget _buildPassword() {
    return ValueListenableBuilder(
      valueListenable: _passwordVisibleNotifier,
      builder: (_, passwordVisible, _) =>
        TextFormField(
          obscureText: !passwordVisible,
          decoration: InputDecoration(labelText: 'Sip password',
            suffixIcon: IconButton(
                icon: Icon(passwordVisible? Icons.visibility_off : Icons.visibility,
                color: Theme.of(context).primaryColor,
              ),
              onPressed: () { _passwordVisibleNotifier.value = !passwordVisible; },
            )
          ),
          validator: (value) { return (value == null || value.isEmpty) ? 'Please enter password.' : null; },
          onChanged: (String? value) { setState(() { if((value!=null) && value.isNotEmpty) _account.sipPassword = value; }); },
        )
    );
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    context.read<SipProvider>().addAccount(_account).then((_) {
      setState(() { _errText = ""; _isRegistering=true; });
    }).catchError((error) {
      setState(() { _errText = error;  });
    });

  }//_submit

}//AccountPageState
