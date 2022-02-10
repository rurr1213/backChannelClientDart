import 'dart:typed_data';
import 'dart:convert';

import '../ftlTools/network/TcpMgr.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/SerDes.dart';
import '../ftlTools/Logger.dart';

class HyperCubeClient {
  final Logger logger;
  final TcpManager tcpManager;
  bool hccOpen = false;
  String? ipAddress = "";
  int numReceivedMsgs = 0;
  int numSentMsgs = 0;
  Function(Uint8List)? onHostTcpReceiveCallback;
  Function()? onHostTcpCloseCallback;

  HyperCubeClient(this.logger) : tcpManager = TcpManager(logger);

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
      logger.add(EVENTTYPE.ERROR, "HCCMgr::processSignallingMsgJson()",
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
    logger.setStateInt("HCCMgr-NumReceivedMsgs", ++numReceivedMsgs);

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
    onHostTcpCloseCallback!();
  }

  void sendBinary(List<int> data, [int size = 0]) {
    logger.setStateInt("DeviceMgr-NumSentMsgs", ++numSentMsgs);
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

  init(
      String _remoteIpAddressString,
      Function(Uint8List) _onHostTcpReceiveCallback,
      Function() onHostTcpCloseCallback) async {
    ipAddress = _remoteIpAddressString;
    onHostTcpReceiveCallback = _onHostTcpReceiveCallback;
    onHostTcpCloseCallback = onHostTcpCloseCallback;

    if (!tcpManager.isOpen()) {
      logger.add(EVENTTYPE.INFO, "HCCMgr",
          "Opening Connection to Server(), at from $ipAddress");
      hccOpen = await tcpManager.open(ipAddress, onTcpReceive, onTcpClose);
      if (hccOpen) {
        logger.add(EVENTTYPE.INFO, "HCCMgr",
            "Openned Connection to Server(), at from $ipAddress");
      }
      //      if (hccOpen) {
      //        Packet packet = Packet(d.data);
      //        packetStreamCtrl.add(packet);
      //      }
    }
  }

  deinit() {
    tcpManager.close();
  }
}
