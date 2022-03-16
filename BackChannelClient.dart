import 'dart:typed_data';
import 'package:base_app/backChannelClientDart/HyperCubeClient.dart';
import '../ftlTools/Logger.dart';
import '/ftlTools/network/PacketCtrl.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/network/Packet.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';

abstract class BackChannelHost {
  onBackChannelOpen(MsgExt msgExt);
  onBackChannelMsg(MsgExt msgExt);
  onBackChannelClose();
}

class BackChannelClient extends HyperCubeClient {
  String remoteIpAddress = "192.168.1.216";
  int remoteIpPort = 5054;
  late PacketCtrl packetCtrl;
  BackChannelHost backChannelClientHost;

  BackChannelClient(Logger logger, this.backChannelClientHost) : super(logger) {
    packetCtrl = PacketCtrl(logger, onMsg);
  }
  init([String _remoteIpAddressString = "", int _remoteIpPort = 0]) async {
    if (_remoteIpAddressString != "") {
      remoteIpAddress = _remoteIpAddressString;
    }
    if (_remoteIpPort != 0) {
      remoteIpPort = _remoteIpPort;
    }

    packetCtrl.init();

    return super.init(remoteIpAddress, remoteIpPort);
  }

  @override
  onPacket(Packet packet) {
    packetCtrl.onPacket(packet);
    packetCtrl.processPackets();
  }

  onMsg(MsgExt msg) {
    if (msg.subSys == SUBSYS_SIG) {
      signallingObject!.processHostMsg(msg);
    } else {
      backChannelClientHost.onBackChannelMsg(msg);
    }
  }

  @override
  bool onConnection() {
    super.onConnection();
    return true;
  }

  @override
  bool onDisconnection() {
    super.onDisconnection();
    return true;
  }

  @override
  onConnectionDataOpen() {
    super.onConnectionDataOpen();
  }

  @override
  onConnectionDataClosed() {}
}
