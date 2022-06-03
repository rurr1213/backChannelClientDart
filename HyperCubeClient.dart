import 'dart:typed_data';
import 'dart:async';

import '../ftlTools/network/TcpMgr.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/HyperCubeMessagesCommon_generated.dart';
import '../ftlTools/network/SerDes.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/Logger.dart';
import '../ftlTools/network/Packet.dart';
import 'SignallingObject.dart';

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

  bool onGroupInfoList(List<GroupInfo> _groupInfoList) {
    _groupInfoList.forEach((element) {
      GroupInfo groupInfo = element;
      String name = groupInfo.groupName;
      logger.add(EVENTTYPE.INFO, "HyperCubeClient::onGroupInfoList()",
          " groupInfo name: $name groupInfo: ${groupInfo.toJson().toString()} ");
    });
    return true;
  }
}
