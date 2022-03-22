import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

import '../ftlTools/network/TcpMgr.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/SerDes.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/Logger.dart';
import '../ftlTools/network/Packet.dart';

enum SignallingObjectState {
  instantiated,
  connected,
  subscribed,
  openForData,
  inDataState,
  outOfDataState,
  closedForData,
  disconnected
}

class SignallingObject {
  final Logger logger;
  final HyperCubeClient hyperCubeClient;
  int numRemotePingAcks = 0;
  int numRemotePings = 0;
  int _systemId = 0;
  SignallingObjectState state = SignallingObjectState.instantiated;

  SignallingObject(this.logger, this.hyperCubeClient);

  setSystemId(int systemId) => _systemId = systemId;

  onConnectionInfoAck(Map<String, dynamic> jsonData) {
    SignallingObjectState prevState = state;
    bool _status = jsonData["status"];
    state = SignallingObjectState.connected;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onConnectionInfoAck()",
        " received onConnectionInfoAck status:$_status, state:$prevState>$state");
  }

  onSubscribeAck(Map<String, dynamic> jsonData) {
    SignallingObjectState prevState = state;
    bool _status = jsonData["status"];
    String _groupName = jsonData["groupName"];
    if ((state == SignallingObjectState.connected) ||
        (state == SignallingObjectState.subscribed) ||
        (state == SignallingObjectState.openForData)) {
      if (state == SignallingObjectState.connected)
        state = SignallingObjectState.subscribed;
      logger.add(EVENTTYPE.INFO, "SignallingObject::onSubscribeAck()",
          " received subscriberAck $_systemId group: $_groupName, status:$_status, state:$prevState>$state");
    } else {
      logger.add(EVENTTYPE.ERROR, "SignallingObject::onSubscribeAck()",
          " received subscriberAck in invalid state:$prevState>$state ");
    }
  }

  onSubscriber(Map<String, dynamic> jsonData) {
    SignallingObjectState prevState = state;
    String _groupName = jsonData["groupName"];
    if ((state == SignallingObjectState.connected) ||
        (state == SignallingObjectState.subscribed) ||
        (state == SignallingObjectState.openForData)) {
      if (state == SignallingObjectState.connected)
        state = SignallingObjectState.subscribed;
      logger.add(EVENTTYPE.INFO, "SignallingObject::onSubscriber()",
          " received subscriber $_systemId group: $_groupName, state:$prevState>$state");
    } else {
      logger.add(EVENTTYPE.ERROR, "SignallingObject::onSubscriber()",
          " received onSubscriber in invalid, state:$prevState>$state");
    }
    onConnectionDataOpen();
  }

  bool processMsgJson(String jsonString) {
    bool processed = false;
    try {
      Map<String, dynamic> jsonData = jsonDecode(jsonString);
      String command = jsonData["command"];
      if (command == "localPing") {
        logger.add(EVENTTYPE.INFO, "SignallingObject::processMsgJson()",
            " received localPing response $jsonString");
        processed = true;
      }
      if (command == "remotePing") {
        if (jsonData["ack"] == true) {
          logger.add(EVENTTYPE.INFO, "SignallingObject::processMsgJson()",
              " received remotePing response $jsonString");
          logger.setStateInt(
              "HyperCubeClient-numRemotePingAcks", ++numRemotePingAcks);
        } else {
          logger.add(EVENTTYPE.INFO, "SignallingObject::processMsgJson()",
              " received remotePing request $jsonString");
          remotePing(true, jsonData["data"]);
          logger.setStateInt(
              "HyperCubeClient-numRemotePings", ++numRemotePings);
        }
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
      if (command == "subscriber") {
        onSubscriber(jsonData);
        processed = true;
      }
      if (command == "subscribeAck") {
        onSubscribeAck(jsonData);
        processed = true;
      }
      if (command == "connectionInfoAck") {
        onConnectionInfoAck(jsonData);
        processed = true;
      }
    } catch (e) {
      logger.add(EVENTTYPE.ERROR, "SignallingObject::processMsgJson()",
          jsonString + ", field not found " + e.toString());
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

  bool processHostMsg(MsgExt msg) {
    return processMsg(msg.data);
  }

  onConnection() {
//    setSystemId(1231);
    sendConnectionInfo("Vortex");
//    createGroup("vortexGroup");
    subscribe("TeamPegasus");
//    localPing();
    //   subscribe("TeamPegasus");
  }

  onDisconnection() {
    state = SignallingObjectState.disconnected;
  }

  onConnectionDataOpen() {
    remotePing();
    hyperCubeClient.onConnectionDataOpen();
    SignallingObjectState prevState = state;
    state = SignallingObjectState.openForData;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onConnectionDataOpen()",
        " state:$prevState>$state");
  }

  onConnectionDataClosed() {
    hyperCubeClient.onConnectionDataClosed();
    SignallingObjectState prevState = state;
    state = SignallingObjectState.closedForData;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onConnectionDataClosed()",
        " state:$prevState>$state");
  }

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

  bool sendConnectionInfo(String connectioName) {
    String jsonString =
        '{"command": "connectionInfo", "connectionName": "$connectioName"}';
    return sendSigMsg(
        jsonString,
        "HyperCubeClient::SignallingObject()::sendConnectionInfo()",
        jsonString);
  }

  bool createGroup(String groupName) {
    String jsonString = '{"command": "createGroup", "groupName": "$groupName"}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::createGroup()", jsonString);
  }

  bool localPing([bool ack = false, String pingData = "localPingFromVortex"]) {
    String jsonString =
        '{"command": "localPing", "ack": $ack, "data": "$pingData"}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::localPing()", jsonString);
  }

  bool remotePing(
      [bool ack = false, String pingData = "remotePingFromVortex"]) {
    String jsonString =
        '{"command": "remotePing", "ack": $ack, "data": "$pingData"}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::remotePing()", jsonString);
  }

  bool echoData([String echoData = "data12345"]) {
    String jsonString = '{"command": "echoData", "data": "$echoData"}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::sendEcho()", jsonString);
  }

  bool subscribe(String _groupName) {
    String jsonString = '{"command": "subscribe", "groupName": "$_groupName"}';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::subscribe()", jsonString);
  }

  bool unsubscribe(String _groupName) {
    String jsonString =
        '{"command": "unsubscribe", "groupName": "$_groupName"}';
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
  int numSentMsgs = 0;
  int numRecvMsgs = 0;
  int numPacketsRecvd = 0;
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
    numPacketsRecvd = 0;
    numRecvMsgs = 0;
    numSentMsgs = 0;
    signallingObject!.onConnection();
    return true;
  }

  bool onDisconnection() {
    signallingObject!.onDisconnection();
    return true;
  }

  onConnectionDataOpen() {}

  onConnectionDataClosed() {}

  bool init([String _remoteIpAddressString = "127.0.0.1", int _ipPort = 0]) {
    ipAddress = _remoteIpAddressString;
    if (_ipPort != 0) ipPort = _ipPort;
    if (ipPort == 0) return false;
    startPeriodicConnectionAttempts(true);

    return true;
  }

  deinit() {
    connectionTimer!.cancel();
    tcpManager.close();
  }

  dynamic onTcpReceive(Uint8List event) {
    Packet packet = Packet(event);
    onPacket(packet);
  }

  onPacket(Packet packet) {
    logger.setStateInt("HyperCubeClient-numPacketsRecvd", ++numPacketsRecvd);
  }

  onMsg(MsgExt msg) {
    logger.setStateInt("HyperCubeClient-numRecvMsgs", ++numRecvMsgs);
  }

  bool checkReadyToOpenForData() {
    if (signallingObject!.state != SignallingObjectState.subscribed) {
      logger.add(EVENTTYPE.ERROR, "HyperCubeClient::checkReadyToOpenForData()",
          "inCorrect state  ${signallingObject!.state} ");
      return false;
    }
    return true;
  }

  bool checkReadyForData() {
    if (signallingObject!.state != SignallingObjectState.inDataState) {
      logger.add(EVENTTYPE.ERROR, "HyperCubeClient::checkReadyForData()",
          "inCorrect state  ${signallingObject!.state} ");
      return false;
    }
    return true;
  }

  setStateAsData(bool yes) {
    SignallingObjectState state = signallingObject!.state;
    SignallingObjectState prevState = state;
    if (yes) {
      if (signallingObject!.state != SignallingObjectState.openForData) {
        logger.add(EVENTTYPE.ERROR, "HyperCubeClient::setStateAsData()",
            "inCorrect state  ${signallingObject!.state} ");
      } else {
        state = signallingObject!.state = SignallingObjectState.inDataState;
        logger.add(EVENTTYPE.INFO, "HyperCubeClient::setStateAsData()",
            " set state as in Data state:$prevState>$state");
      }
    } else {
      if (signallingObject!.state != SignallingObjectState.closedForData) {
        logger.add(EVENTTYPE.ERROR, "HyperCubeClient::setStateAsData()",
            "inCorrect state  ${signallingObject!.state} ");
      } else {
        state = signallingObject!.state = SignallingObjectState.outOfDataState;
        logger.add(EVENTTYPE.INFO, "HyperCubeClient::setStateAsData()",
            " set state as in Data state:$prevState>$state");
      }
    }
    return true;
  }

  dynamic onTcpClose() {
    logger.add(EVENTTYPE.WARNING, "HyperCubeClient::onTcpClose()",
        "connection to $ipAddress:$ipPort closed");
    onDisconnection();
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
