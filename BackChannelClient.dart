import 'package:base_app/backChannelClientDart/HyperCubeClient.dart';
import 'SignallingObject.dart';
import '../ftlTools/Logger.dart';
import '../ftlTools/network/PacketCtrl.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/network/Packet.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/HyperCubeMessagesCommon_generated.dart';

abstract class BackChannelHost {
  onBackChannelInfo(String groupName);
  bool onBackChannelOpenStream(MsgExt msgExt);
  onBackChannelMsg(MsgExt msgExt);
  bool onBackChannelCloseStream();
}

class BackChannelClient extends HyperCubeClient {
  late PacketCtrl packetCtrl;
  BackChannelHost backChannelHost;

  BackChannelClient(Logger logger, this.backChannelHost) : super(logger) {
    packetCtrl = PacketCtrl(logger, onMsg);
  }

  init(
      {String remoteIpAddressString = HyperCubeClient.DEFAULT_SERVERIP,
      int remoteIpPort = HyperCubeClient.DEFAULT_SERVERPORT}) {
    packetCtrl.init();
    return super.init(
        remoteIpAddressString: remoteIpAddressString,
        remoteIpPort: remoteIpPort);
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
              onOpenStream(msgExt);
              break;
            case DISCOVERY_CLOSESOCKET:
              onCloseStream();
              break;
          }
        }
        break;
      default:
        {
          onMsgForHost(msgExt);
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
    onCloseStream();
    return true;
  }

  onMsgForHost(MsgExt msgExt) {
    // if (!checkReadyForData()) return;
    backChannelHost.onBackChannelMsg(msgExt);
  }

  @override
  onConnectionDataOpen(String groupName) {
    super.onConnectionDataOpen(groupName);
    backChannelHost.onBackChannelInfo(groupName);
  }

  @override
  onConnectionDataClosed() {
    super.onConnectionDataClosed();
    onCloseStream();
  }

  onOpenStream(MsgExt msgExt) {
    if (signallingObject!.state != SignallingObjectState.inDataState) {
      bool status = backChannelHost.onBackChannelOpenStream(msgExt);
      setStateAsData(status);
    }
  }

  onCloseStream() {
    if ((signallingObject!.state == SignallingObjectState.inDataState) ||
        (signallingObject!.state == SignallingObjectState.connected) ||
        (signallingObject!.state == SignallingObjectState.disconnected)) {
      bool status = backChannelHost.onBackChannelCloseStream();
      setStateAsData(!status);
    }
  }

  bool searchForGroupsWithKeyword(String keyword) {
    return signallingObject!.getGroups(keyword);
  }
}
