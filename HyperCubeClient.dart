import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

import '../ftlTools/network/TcpMgr.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/SerDes.dart';
import '../ftlTools/Logger.dart';

class SignallingObject {
  final Logger logger;
  final HyperCubeClient hyperCubeClient;
  String _groupName = "";
  int _systemId = 0;

  SignallingObject(this.logger, this.hyperCubeClient);

  bool processMsgJson(String jsonString) {
    bool processed = false;
    try {
      Map<String, dynamic> jsonData = jsonDecode(jsonString);
      String command = jsonData["command"];
      if (command == "localPing") {
        logger.add(EVENTTYPE.INFO, "SignallingObject::processMsgJson()",
            " received localPing $jsonString");
        processed = true;
      }
      if (command == "echoData") {
        String data = jsonData["data"];
        Map jsonResponse = {"command": command, "data": data};
        String jsonResponseString = jsonEncode(jsonResponse);
        MsgCmd msgCmd = MsgCmd(jsonResponseString);
        hyperCubeClient.sendMsg(msgCmd);
        processed = true;
      }
    } catch (e) {
      logger.add(
          EVENTTYPE.ERROR,
          "HyperCubeClient()::processSignallingMsgJson()",
          "field not found " + e.toString());
    }
    return processed;
  }

  bool processMsg(Uint8List event) {
    bool proceesed = false;
    SerDes sdm = SerDes(event);
    SigMsg sigMsg = SigMsg("");
    sigMsg.deserialize(sdm);
    switch (sigMsg.subSys) {
      case SUBSYS_SIG:
        switch (sigMsg.command) {
          case SIG_JSON:
            proceesed = processMsgJson(sigMsg.jsonData);
            break;
          default:
        }
        break;
      default:
    }
    return proceesed;
  }

  onConnection() {
    localPing();
  }

  onDisconnection() {}

  bool sendSigMsg(
      String jsonString, String callingFunctionName, String statusString) {
    SigMsg sigMsg = SigMsg(jsonString);
    bool stat = hyperCubeClient.sendMsg(sigMsg);

    if (stat)
      logger.add(
          EVENTTYPE.INFO, callingFunctionName, statusString + " succeded");
    else
      logger.add(
          EVENTTYPE.WARNING, callingFunctionName, statusString + " Failed");
    return stat;
  }

  bool createGroup() {
    String jsonString =
        '{ "command": "createGroup"}, "systemId": $_systemId, groupName": $_groupName}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::createGroup()", jsonString);
  }

  bool localPing() {
    String pingData = "12345";
    String jsonString =
        '{"command": "localPing", "systemId": $_systemId, "data": $pingData}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::localPing()", jsonString);
  }

  bool sendEcho() {
    String echoData = "12345";
    String jsonString = '{"command": "echoData", "data": $echoData}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::sendEcho()", jsonString);
  }

  bool subscribe(int _groupId) {
    String jsonString =
        '{ {"command": "subscribe"}, {"systemId": $_systemId}, {"groupId": $_groupId}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::subscribe()", jsonString);
  }
}

class HyperCubeClient {
  final Logger logger;
  final TcpManager tcpManager;
  SignallingObject? signallingObject;
  bool connectionOpen = false;
  String? ipAddress = "";
  int ipPort = 0;
  int numConnectionAttempts = 0;
  int numReceivedMsgs = 0;
  int numSentMsgs = 0;
  Function(Uint8List)? onHostTcpReceiveCallback;
  Function()? onHostTcpCloseCallback;
  Timer? connectionTimer;
  int _connectionPeriodSecs = 10;
  bool alreadyWarnedOfConnectFailure = false;

  HyperCubeClient(this.logger) : tcpManager = TcpManager(logger) {
    signallingObject = SignallingObject(logger, this);
  }

  Future<bool> openConnection() async {
    connectionTimer = null;
    if (!tcpManager.isOpen()) {
      connectionOpen = await tcpManager.open(
          onTcpReceive, onTcpClose, ipAddress, ipPort, false);
      logger.setStateInt(
          "HyperCubeClient-NumConnectionAttempt", ++numConnectionAttempts);

      if (connectionOpen) {
        logger.add(EVENTTYPE.INFO, "HyperCubeClient::openConnection()",
            "Opened connection to $ipAddress:$ipPort");
        alreadyWarnedOfConnectFailure = false;
        onConnection();
      } else {
        if (!alreadyWarnedOfConnectFailure)
          logger.add(EVENTTYPE.WARNING, "HyperCubeClient::openConnection()",
              "connection failed to $ipAddress:$ipPort");
        alreadyWarnedOfConnectFailure = true;
      }
      //      if (hccOpen) {
      //        Packet packet = Packet(d.data);
      //        packetStreamCtrl.add(packet);
      //      }
    }
    return connectionOpen;
  }

  onConnectionTimer(Timer timer) async {
    if (!connectionOpen) {
      connectionOpen = await openConnection();
    } else {
      timer.cancel();
    }
  }

  startPeriodicConnectionAttempts([bool startNow = false]) {
    connectionTimer = Timer.periodic(
        Duration(seconds: _connectionPeriodSecs), onConnectionTimer);
    if (startNow) {
      onConnectionTimer(Timer(Duration.zero, () {}));
    }
  }

  bool onConnection() {
    signallingObject!.onConnection();
    return true;
  }

  bool onDisconnection() {
    signallingObject!.onDisconnection();
    return true;
  }

  bool init(Function(Uint8List) _onHostTcpReceiveCallback,
      Function() _onHostTcpCloseCallback,
      [String _remoteIpAddressString = "127.0.0.1", int _ipPort = 0]) {
    ipAddress = _remoteIpAddressString;
    if (_ipPort != 0) ipPort = _ipPort;
    if (ipPort == 0) return false;
    onHostTcpReceiveCallback = _onHostTcpReceiveCallback;
    onHostTcpCloseCallback = _onHostTcpCloseCallback;

    startPeriodicConnectionAttempts(true);

    return true;
  }

  deinit() {
    connectionTimer!.cancel();
    tcpManager.close();
  }

  dynamic onTcpReceive(Uint8List event) {
    logger.setStateInt("HyperCubeClient-NumReceivedMsgs", ++numReceivedMsgs);

    SerDes sdm = SerDes(event);
    Msg msg = Msg();
    msg.deserialize(sdm);
    if (msg.subSys == SUBSYS_SIG) {
      signallingObject!.processMsg(event);
    } else {
      onHostTcpReceiveCallback!(event);
    }
  }

  dynamic onTcpClose() {
    logger.add(EVENTTYPE.WARNING, "HyperCubeClient::onTcpClose()",
        "connection to $ipAddress:$ipPort closed");
    onDisconnection();
    onHostTcpCloseCallback!();
    connectionOpen = false;
    startPeriodicConnectionAttempts(); // try again
  }

  void sendBinary(List<int> data, [int size = 0]) {
    logger.setStateInt("HyperCubeClient-NumSentMsgs", ++numSentMsgs);
    tcpManager.sendBinary(data, size);
  }

  bool sendMsg(Msg msg) {
    const int bufferSize = 1024 * 8;
    Uint8List data = Uint8List(bufferSize);
    SerDes sd = SerDes(data);
    int size = msg.serialize(sd);
    sendBinary(data, size);
    assert(size < bufferSize); // else buffer is too small
    return size != 0;
  }
}
