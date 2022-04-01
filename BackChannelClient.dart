import 'package:base_app/backChannelClientDart/HyperCubeClient.dart';
import '../ftlTools/Logger.dart';
import '../ftlTools/network/PacketCtrl.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/network/Packet.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';

abstract class BackChannelHost {
  bool onBackChannelOpen(MsgExt msgExt);
  onBackChannelMsg(MsgExt msgExt);
  bool onBackChannelClose();
}

class BackChannelClient extends HyperCubeClient {
//  String remoteIpAddress = "192.168.1.216";
  String remoteIpAddress = "3.141.6.1";
  int remoteIpPort = 5054;
  late PacketCtrl packetCtrl;
  BackChannelHost backChannelHost;

  BackChannelClient(Logger logger, this.backChannelHost) : super(logger) {
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
    super.onPacket(packet);
    packetCtrl.onPacket(packet);
    packetCtrl.processPackets();
  }

  @override
  onMsg(MsgExt msgExt) {
    super.onMsg(msgExt);
    switch (msgExt.getMsg().subSys) {
      case SUBSYS_SIG:
        signallingObject!.processHostMsg(msgExt);
        break;
      case SUBSYS_DISCOVERY:
        {
          switch (msgExt.getMsg().command) {
            case DISCOVERY_HELLO:
              bool status = backChannelHost.onBackChannelOpen(msgExt);
              setStateAsData(status);
              break;
            case DISCOVERY_CLOSESOCKET:
              bool status = backChannelHost.onBackChannelClose();
              setStateAsData(!status);
              break;
          }
        }
        break;
      default:
        {
          // if (!checkReadyForData()) return;
          backChannelHost.onBackChannelMsg(msgExt);
        }
        break;
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
  onConnectionDataClosed() {
    backChannelHost.onBackChannelClose();
  }
}
