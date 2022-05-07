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
  ConnectionInfo connectionInfo = ConnectionInfo();

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
    // String _groupName = jsonData["groupName"];

    if (!_status) {
      logger.add(EVENTTYPE.WARNING, "SignallingObject::onSubscribeAck()",
          " received onSubscribeAck FAIL status:$_status, state:$prevState>$state");
      state = SignallingObjectState.connected;
      onConnectionDataClosed();
      return;
    }

    switch (state) {
      case SignallingObjectState.connected:
      case SignallingObjectState.closedForData:
        state = SignallingObjectState.subscribed;
        break;
      case SignallingObjectState.openForData:
        break;
      default:
        logger.add(EVENTTYPE.ERROR, "SignallingObject::onSubscribeAck()",
            " received subscriberAck in invalid state:$prevState>$state ");
        break;
    }
  }

  onUnsubscribeAck(Map<String, dynamic> jsonData) {
    SignallingObjectState prevState = state;
    bool _status = jsonData["status"];
    String _groupName = jsonData["groupName"];
    state = SignallingObjectState.connected;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onSubscribeAck()",
        " received subscriberAck $_systemId group: $_groupName, status:$_status, state:$prevState>$state");
    //if (state != SignallingObjectState.closedForData) onConnectionDataClosed();
  }

  onSubscriber(Map<String, dynamic> jsonData) {
    bool stat = true;
    SignallingObjectState prevState = state;
    String _groupName = jsonData["groupName"];
    switch (state) {
      case SignallingObjectState.connected:
      case SignallingObjectState.subscribed:
      case SignallingObjectState.openForData:
      case SignallingObjectState.closedForData:
        state = SignallingObjectState.openForData;
        break;
      default:
        stat = false;
        logger.add(EVENTTYPE.ERROR, "SignallingObject::onSubscriber()",
            " received onSubscriber in invalid, state:$prevState>$state");
        break;
    }
    if (stat) onConnectionDataOpen(_groupName);
  }

  onUnsubscriber(Map<String, dynamic> jsonData) {
    SignallingObjectState prevState = state;
    String _groupName = jsonData["groupName"];
    logger.add(EVENTTYPE.INFO, "SignallingObject::onUnsubscriber()",
        " received subscriber $_systemId group: $_groupName, state:$prevState>$state");
    if (state != SignallingObjectState.closedForData) onConnectionDataClosed();
  }

  onGetGroupsAck(Map<String, dynamic> jsonData) {
    SignallingObjectState prevState = state;
    bool _status = jsonData["status"];
    String _searchWord = jsonData["searchWord"];
    List _groupInfoList = jsonData["groupInfoList"];

    logger.add(EVENTTYPE.INFO, "SignallingObject::onGetGroupsAck()",
        " received onGetGroupsAck $_systemId searchWord: $_searchWord, status:$_status, items: ${_groupInfoList.length} state:$prevState>$state");
    _groupInfoList.forEach((element) {
      String name = element["name"];
      logger.add(EVENTTYPE.INFO, "SignallingObject::onGetGroupsAck()",
          " groupInfo name $name ");
    });
    //if (state != SignallingObjectState.closedForData) onConnectionDataClosed();
  }

  onClosedForData(Map<String, dynamic> jsonData) {
    SignallingObjectState prevState = state;
    logger.add(EVENTTYPE.INFO, "SignallingObject::onClosedForData()",
        " received $_systemId state:$prevState>$state");
    onConnectionDataClosed();
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
      if (command == "connectionInfoAck") {
        onConnectionInfoAck(jsonData);
        processed = true;
      }
      if (command == "subscriber") {
        onSubscriber(jsonData);
        processed = true;
      }
      if (command == "unsubscriber") {
        onUnsubscriber(jsonData);
        processed = true;
      }
      if (command == "subscribeAck") {
        onSubscribeAck(jsonData);
        processed = true;
      }
      if (command == "unsubscribeAck") {
        onUnsubscribeAck(jsonData);
        processed = true;
      }
      if (command == "getGroupsAck") {
        onGetGroupsAck(jsonData);
        processed = true;
      }
      if (command == "closedForData") {
        onClosedForData(jsonData);
        processed = true;
      }
    } catch (e) {
      logger.add(EVENTTYPE.ERROR, "SignallingObject::processMsgJson()",
          jsonString + ", field not found " + e.toString());
    }
    return processed;
  }

  bool processMsg(MsgExt msgExt) {
    bool proceesed = false;
    SigMsg sigMsg = msgExt.getSigMsg();
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

  bool processHostMsg(MsgExt msgExt) {
    return processMsg(msgExt);
  }

  onConnection() {
//    setSystemId(1231);
    sendConnectionInfo();
//    createGroup("vortexGroup");
//    subscribe("TeamPegasus");
//    localPing();
    //   subscribe("TeamPegasus");
    getGroups("Team");
  }

  onDisconnection() {
    state = SignallingObjectState.disconnected;
  }

  onConnectionDataOpen(String _groupName) {
    remotePing();
    hyperCubeClient.onConnectionDataOpen(_groupName);
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

  bool sendConnectionInfo() {
    connectionInfo.serverIpAddress = hyperCubeClient.ipAddress;

    Map<String, dynamic> jConnectionInfoCmd = {
      "command": "connectionInfo",
      "connectionInfo": connectionInfo.toJson()
    };

    String jsonString = jsonEncode(jConnectionInfoCmd);

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
    if ((state != SignallingObjectState.connected) &&
        (state != SignallingObjectState.closedForData)) return false;
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

  bool getGroups(String _searchWord, {startingIndex = 0, maxItems = 10}) {
    String jsonString =
        '{"command": "getGroups", "searchWord": "$_searchWord", "startingIndex": $startingIndex, "maxItems":$maxItems }';
    return sendSigMsg(jsonString,
        "HyperCubeClient::SignallingObject()::subscribe()", jsonString);
  }
}

class HyperCubeClient {
  final Logger logger;
  final TcpManager tcpManager;
  SignallingObject? signallingObject;
  bool connectionOpen = false;
  String ipAddress = "";
  int ipPort = 0;
  int numConnectionAttempts = 0;
  int numSentMsgs = 0;
  int numRecvMsgs = 0;
  Timer? connectionTimer;
  int _connectionPeriodSecs = 10;
  String connectedGroupName = "";
  bool alreadyWarnedOfConnectFailure = false;

  static const String DEFAULT_SERVERIP = "127.0.0.1";
  static const int DEFAULT_SERVERPORT = 5054;

  HyperCubeClient(this.logger) : tcpManager = TcpManager("Hyper", logger) {
    signallingObject = SignallingObject(logger, this);
  }

  Future<bool> openConnection() async {
    connectionTimer = null;

    if (!tcpManager.isOpen()) {
      connectionOpen = await tcpManager.open(
          onTcpReceive, onTcpClose, ipAddress, ipPort, false);
      logger.setStateInt(
          "HyperCubeClient-NumConnectionAttempt", ++numConnectionAttempts);
      logger.setStateString("HyperCubeClient-ConnectionState",
          connectionOpen ? "connected" : "disconnected");

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
    numRecvMsgs = 0;
    numSentMsgs = 0;
    signallingObject!.onConnection();
    return true;
  }

  bool onDisconnection() {
    signallingObject!.onDisconnection();
    return true;
  }

  onConnectionDataOpen(String _groupName) {
    connectedGroupName = _groupName;
  }

  onConnectionDataClosed() {}

  bool init(
      {String remoteIpAddressString = DEFAULT_SERVERIP,
      int remoteIpPort = DEFAULT_SERVERPORT}) {
    ipAddress = remoteIpAddressString;
    ipPort = remoteIpPort;
    if (ipPort == 0) return false;
    startPeriodicConnectionAttempts(true);

    return true;
  }

  deinit() {
    connectionTimer!.cancel();
    tcpManager.close();
  }

  bool subscribe(String groupName) {
    return signallingObject!.subscribe(groupName);
  }

  bool unsubscribe(String groupName) {
    return signallingObject!.unsubscribe(groupName);
  }

  dynamic onTcpReceive(Uint8List event) {
    Packet packet = Packet(event);
    onPacket(packet);
  }

  onPacket(Packet packet) {}

  onMsg(MsgExt msg) {
    logger.setStateInt("HyperCubeClient-NumRecvMsgs", ++numRecvMsgs);
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
      switch (signallingObject!.state) {
        case SignallingObjectState.openForData:
          state = signallingObject!.state = SignallingObjectState.inDataState;
          logger.add(EVENTTYPE.INFO, "HyperCubeClient::setStateAsData()",
              " set state as in Data state:$prevState>$state");
          break;
        default:
          logger.add(EVENTTYPE.WARNING, "HyperCubeClient::setStateAsData()",
              "inCorrect state  ${signallingObject!.state} ");
          break;
      }
    } else {
      switch (signallingObject!.state) {
        case SignallingObjectState.disconnected:
        case SignallingObjectState.closedForData:
        case SignallingObjectState.inDataState:
          state =
              signallingObject!.state = SignallingObjectState.outOfDataState;
          logger.add(EVENTTYPE.INFO, "HyperCubeClient::setStateAsData()",
              " set state as in Data state:$prevState>$state");
          break;
        default:
          logger.add(EVENTTYPE.WARNING, "HyperCubeClient::setStateAsData()",
              "inCorrect state  ${signallingObject!.state} ");
          break;
      }
    }
    return true;
  }

  dynamic onTcpClose() {
    logger.add(EVENTTYPE.WARNING, "HyperCubeClient::onTcpClose()",
        "connection to $ipAddress:$ipPort closed");
    onDisconnection();
    connectionOpen = false;
    logger.setStateString("HyperCubeClient-ConnectionState",
        connectionOpen ? "connected" : "disconnected");
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

  setConnectionInfo(ConnectionInfo connectionInfo) {
    signallingObject!.connectionInfo = connectionInfo;
  }
}
