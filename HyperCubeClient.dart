import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

import '../ftlTools/network/TcpMgr.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/SerDes.dart';
import '../ftlTools/Logger.dart';

class HyperCubeClient {
  final Logger logger;
  final TcpManager tcpManager;
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

  HyperCubeClient(this.logger) : tcpManager = TcpManager(logger);

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

  bool processSignallingMsgJson(String jsonString) {
    bool processed = false;
    try {
      Map<String, dynamic> jsonData = jsonDecode(jsonString);
      String command = jsonData["command"];
      if (command == "localPing") {
        processed = true;
      }
      if (command == "echoData") {
        String data = jsonData["data"];
        Map jsonResponse = {"command": command, "data": data};
        String jsonResponseString = jsonEncode(jsonResponse);
        MsgCmd msgCmd = MsgCmd(jsonResponseString);
        sendMsg(msgCmd);
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

  bool processSignallingMsg(Uint8List event) {
    bool proceesed = false;
    SerDes sdm = SerDes(event);
    SigMsg sigMsg = SigMsg("");
    sigMsg.deserialize(sdm);
    switch (sigMsg.subSys) {
      case SUBSYS_SIG:
        switch (sigMsg.command) {
          case SIG_JSON:
            proceesed = processSignallingMsgJson(sigMsg.jsonData);
            break;
          default:
        }
        break;
      default:
    }
    return proceesed;
  }

  dynamic onTcpReceive(Uint8List event) {
    logger.setStateInt("HyperCubeClient-NumReceivedMsgs", ++numReceivedMsgs);

    SerDes sdm = SerDes(event);
    Msg msg = Msg();
    msg.deserialize(sdm);
    if ((msg.subSys == SUBSYS_SIG) && (msg.command != SIG_JSON)) {
      processSignallingMsg(event);
    } else {
      onHostTcpReceiveCallback!(event);
    }
  }

  dynamic onTcpClose() {
    logger.add(EVENTTYPE.WARNING, "HyperCubeClient::onTcpClose()",
        "connection to $ipAddress:$ipPort closed");

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
