import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:siprix_voip_sdk/accounts_model.dart';
import 'package:siprix_voip_sdk/calls_model.dart';
import 'package:siprix_voip_sdk/logs_model.dart';
import 'package:siprix_voip_sdk/network_model.dart';
import 'package:siprix_voip_sdk/siprix_voip_sdk.dart';

import 'package:shared_preferences/shared_preferences.dart';


class SipProvider extends ChangeNotifier {
  static const String kAccountKey="sipAccount";
  static const int kEmptyCallId=0;

  SipProvider() {
    SiprixVoipSdk().accListener = AccStateListener(
      regStateChanged : _onRegStateChanged
    );

    SiprixVoipSdk().callListener = CallStateListener(
      playerStateChanged: null,//_onPlayerStateChanged,
      proceeding : null,//_onProceeding,
      incoming : _onCallIncomingSip,
      incomingPush : null,//_onIncomingPush,
      acceptNotif: _onAcceptNotif,
      connected : _onCallConnected,
      terminated : _onCallTerminated,
      transferred : null,//onTransferred,
      redirected : null,//onRedirected,
      videoUpgraded : null,//onVideoUpgraded,
      videoUpgradeRequested : null,//onVideoUpgradeRequested,
      dtmfReceived : null,//onDtmfReceived,
      switched : _onCallSwitched,
      held : _onCallHeld
    );
  }

  void Function(RegState state, String response)? accRegStateChanged;
  void Function()? accDeleted;

  //Current account (null if not aded yet)
  AccountModel? _curAccount;

  //Current call/callId and list of calls
  CallModel? _curCall;
  int _curCallId = kEmptyCallId;
  final List<CallModel> _calls = [];

  bool _initialized = false;
  Timer? _durationTimer;

  //Account getters
  RegState get accountRegState => _curAccount?.regState ?? RegState.removed;
  String get accountStatus => (_curAccount!=null) ? _curAccount!.regState.toString() : "Not added yet";
  String get accountUri => _curAccount?.uri ?? "-";
  bool get isAccountAdded => (_curAccount!=null);
  bool get isRegistered => (_curAccount!=null) ? (_curAccount!.regState==RegState.success) : false;

  //Call getters
  String get callStatus => (_curCall!=null) ? _curCall!.state.toString() : "Idle";
  bool get isMuted => (_curCall!=null) ? _curCall!.isMicMuted : false;

  CallModel? get currentCall => _curCall;
  bool get inCall => currentCall != null;
  bool get isIncomingCall => (currentCall?.isIncoming ?? false);
  bool get isOnHold => currentCall?.state == CallState.held;

  String get formattedDuration => currentCall?.durationStr ?? '00:00';
  String? get remoteNumber => currentCall?.remoteExt;
  String? get remoteDisplayName => currentCall?.displName ?? currentCall?.remoteExt;


  Future<void> initializeSiprix() async {
    if (_initialized) return;

    String license = '';//TODO put license here
    final LogLevel logLevelFile = LogLevel.debug;
    final LogLevel logLevelConsole = LogLevel.info;

    final ini = InitData()
      ..license = license
      ..logLevelFile = logLevelFile
      ..logLevelIde = logLevelConsole
      ..useDnsSrv = false;

    SiprixVoipSdk().initialize(ini);
    _initialized = true;
  }

  void _onCallSwitched(int callId) {
    if(_curCallId != callId) {
      _curCallId = callId;

      final int index = _calls.indexWhere((c) => c.myCallId==_curCallId);
      _curCall = (index == -1) ? null : _calls[index];
      notifyListeners();
    }
  }

  void _onCallIncomingSip(int callId, int accId, bool withVideo, String hdrFrom, String hdrTo) {
    String accUri = _curAccount?.uri ?? "Unknown@URI";
    bool hasSecureMedia = _curAccount?.hasSecureMedia?? false;

    CallModel newCall = CallModel(callId, accUri, CallsModel.parseExt(hdrFrom), true, hasSecureMedia, withVideo);
    newCall.displName = CallsModel.parseDisplayName(hdrFrom);
    _calls.add(newCall);

    if(_curCallId == kEmptyCallId) {
       _curCallId = callId;
       _curCall = newCall;
    }

    _startDurationTicker();
    notifyListeners();
  }

  void _onAcceptNotif(int callId, bool withVideo) {
    //Handle tap 'Accept' on notification (Android only)
    int index = _calls.indexWhere((c) => c.myCallId==callId);
    if(index != -1) _calls[index].accept(withVideo);
    notifyListeners();
  }

  void _onCallConnected(int callId, String from, String to, bool withVideo) {
    int index = _calls.indexWhere((c) => c.myCallId==callId);
    if(index != -1) _calls[index].onConnected(from, to, withVideo);

    if(_curCallId == callId) {
      _startDurationTicker();
    }

    notifyListeners();
  }

  void _onCallTerminated(int callId, int statusCode) {
    int index = _calls.indexWhere((c) => c.myCallId==callId);
    if(index != -1) _calls.removeAt(index);

    if(_curCallId == callId) {
      _stopDurationTicker();
    }

    notifyListeners();
  }

  void _onCallHeld(int callId, HoldState s) {
    int index = _calls.indexWhere((c) => c.myCallId==callId);
    if(index != -1) _calls[index].onHeld(s);
    notifyListeners();
  }

  // ---------------- Account actions ----------------

  Future<void> addAccount(AccountModel acc) async {
    if (!_initialized) {
      throw StateError('SipProvider not initialized. Call initializeSiprix() first.');
    }
    if((_curAccount != null)&&(_curCall==null)) {
      SiprixVoipSdk().deleteAccount(_curAccount!.myAccId);
      _curAccount = null;
    }

    _internalAddAccount(acc);
  }

  Future<void> deleteAccount() async {
    try {
      if((_curAccount != null)&&(_curCall==null)) {
        int accId = _curAccount!.myAccId;
        await SiprixVoipSdk().deleteAccount(accId);
        _curAccount = null;

        _saveAccount(null);
        accDeleted?.call();
        debugPrint('Deleted account accId:$accId');
      }
    } on PlatformException catch (err) {
      debugPrint('Can\'t delete account: ${err.code} ${err.message}');
      return Future.error((err.message==null) ? err.code : err.message!);
    }
  }

  void _internalAddAccount(AccountModel acc, {bool saveChanges=true}) async {
    //Modify some properties if required
    //acc.stunServer = "stun.l.google.com:19302";
    acc.port ??= Random().nextInt(65535-1024) + 1024;
    acc.instanceId ??= await SiprixVoipSdk().genAccInstId();
    //acc.ringTonePath = MyApp.getRingtonePath();
    //acc.xheaders = {"X-Token" : token};

    //Set as current
    _curAccount = acc;

    // Add account
    try {
      _curAccount?.myAccId = await SiprixVoipSdk().addAccount(acc) ?? 0;
      if(saveChanges) _saveAccount(acc);
    } on PlatformException catch (err) {
      if(err.code == SiprixVoipSdk.eDuplicateAccount.toString()) {
        int existingAccId = err.details;
        _curAccount?.myAccId = existingAccId;
      } else {
        _curAccount = null;
        rethrow;
      }
    } catch (e) {
      _curAccount = null;
      rethrow;
    }
  }

  void _saveAccount(AccountModel? acc) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(kAccountKey, (acc!=null) ? jsonEncode(acc) : "");
    });
  }

  Future<bool> loadSavedAccount() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String accJsonStr = prefs.getString(kAccountKey) ?? '';
      if(accJsonStr.isEmpty) return false;

      _internalAddAccount(AccountModel.fromJson(jsonDecode(accJsonStr)), saveChanges:false);
      return true;
    } catch (e) {
      debugPrint("Can't load account error:$e");
      return false;
    }
  }

  Future<void> refreshRegistration() async {
    try {
      if(_curAccount != null) {
        int expireSec = 300;//how long server should remember this account
        _curAccount!.expireTime =expireSec;
        _curAccount!.regState = RegState.inProgress;
        SiprixVoipSdk().registerAccount(_curAccount!.myAccId, expireSec);
      }
    } on PlatformException catch (err) {
      debugPrint('Can\'t refresh accounts registration: ${err.code} ${err.message}');
      return Future.error((err.message==null) ? err.code : err.message!);
    }
  }

  ///Unregister account
  Future<bool> unregister() async {
    try {
      if(_curAccount != null) {
        await SiprixVoipSdk().unRegisterAccount(_curAccount!.myAccId);

        //Update UI
        _curAccount!.expireTime = 0;
        _curAccount!.regState = RegState.inProgress;        notifyListeners();
        return true;
      }else{
        return false;
      }
    } on PlatformException catch (err) {
      debugPrint('Can\'t unregister account: ${err.code} ${err.message}');
      notifyListeners();
      return false;
    }
  }

  void _onRegStateChanged(int accId, RegState state, String response) {
    accRegStateChanged?.call(state, response);

    if (_curAccount!=null && _curAccount!.myAccId == accId) {
      _curAccount!.regState = state;
      _curAccount!.regText = response;
      notifyListeners();
    }
  }

  Future<bool> makeCall(String number, {bool withVideo = false}) async {
    if (_curAccount==null) {
      notifyListeners();
      return false;
    }
    else if (_curAccount!.regState == RegState.failed) {
      notifyListeners();
      return false;
    }

    try {
      notifyListeners();

      await _invite(number);

      _startDurationTicker();
      notifyListeners();
      return true;
    } catch (e) {
      notifyListeners();
      return false;
    }
  }

  Future<void> _invite(String number,{bool withVideo = false}) async {
    final cleanNumber = number.replaceAll(RegExp(r'[^\d+]'), '');

    final dest = CallDestination(cleanNumber, _curAccount!.myAccId, withVideo);
    int callId = await SiprixVoipSdk().invite(dest) ?? 0;

    CallModel newCall = CallModel(callId, _curAccount!.uri, dest.toExt, false, _curAccount!.hasSecureMedia, dest.withVideo);
    _calls.add(newCall);

    if(_curCallId == kEmptyCallId) {
      _curCallId = callId;
      _curCall = newCall;
    }
  }

  Future<void> answerCall({bool withVideo = false}) async {
    if (_curCall == null) return;

    notifyListeners();

    await _curCall!.accept(withVideo);
    _startDurationTicker();
    notifyListeners();
  }

  Future<void> rejectCall() async {
    if (_curCall == null) return;

    await _curCall!.reject();
    _stopDurationTicker();
    notifyListeners();
  }

  Future<void> endCall() async {
    if (_curCall == null) return;

    await _curCall!.bye();
    _stopDurationTicker();
    notifyListeners();
  }

  Future<void> toggleHold() async {
    if (_curCall == null) return;

    await _curCall!.hold();
    notifyListeners();
  }

  Future<void> toggleMute() async {
    if (_curCall != null) {
      await _curCall?.muteMic(!_curCall!.isMicMuted);
      notifyListeners();   // refresh UI
    }
  }

  void stop() {
    _stopDurationTicker();
    _curCall = null;
    notifyListeners();
  }

  void _startDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _curCall?.calcDuration();
      notifyListeners();
    });
  }

  void _stopDurationTicker() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  @override
  void dispose() {
    _stopDurationTicker();
    super.dispose();
  }
}
