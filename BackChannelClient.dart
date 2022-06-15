import 'package:base_app/backChannelClientDart/HyperCubeClient.dart';
import 'SignallingObject.dart';
import '../ftlTools/Logger.dart';
import '../ftlTools/network/PacketCtrl.dart';
import '../ftlTools/network/MsgExt.dart';
import '../ftlTools/network/Packet.dart';
import '../ftlTools/network/CommonCppDartCode/Messages/MessagesCommon_generated.dart';
import 'package:firedart/firedart.dart';

abstract class BackChannelHost {
  onBackChannelInfo(String groupName);
  bool onBackChannelOpenStream(MsgExt msgExt);
  onBackChannelMsg(MsgExt msgExt);
  bool onBackChannelCloseStream();
  bool onBackChannelConnectionClosed();
}

class CloudConfigInfo {
  static String masterIpAddressKeyValue = "masterIpAddress";
  static String masterIpPortKeyValue = "masterIpPort";
  static String backupIpAddressKeyValue = "backupIpAddress";
  static String backupIpPortKeyValue = "backupIpPort";
  String masterIpAddress = HyperCubeClient.DEFAULT_SERVERIP;
  String backupIpAddress = HyperCubeClient.DEFAULT_SERVERIP;
  int masterIpPort = HyperCubeClient.DEFAULT_SERVERPORT;
  int backupIpPort = HyperCubeClient.DEFAULT_SERVERPORT;
  Map<String, dynamic> toMap() {
    return {
      masterIpAddressKeyValue: masterIpAddress,
      masterIpPortKeyValue: masterIpPort,
      backupIpAddressKeyValue: backupIpAddress,
      backupIpPortKeyValue: backupIpPort
    };
  }
}

class BackChannelClient extends HyperCubeClient {
  late PacketCtrl packetCtrl;
  BackChannelHost backChannelHost;
  CloudConfigInfo cloudConfigInfo = CloudConfigInfo();

  BackChannelClient(Logger logger, this.backChannelHost) : super(logger) {
    packetCtrl = PacketCtrl(logger, onMsg);
  }

  initCloudConfig() {
    var collection = Firestore.instance.collection("HyperCube");
    var document = collection.document("globalConfig");
    CloudConfigInfo initCloudConfingInfo = CloudConfigInfo();
    var map = initCloudConfingInfo.toMap();
    document.update(map);
  }

  Future<bool> getCloudConfig(CloudConfigInfo _cloudConfigInfo) async {
    bool found = false;
    try {
      var collection = Firestore.instance.collection("HyperCube");
      DocumentReference documentReference = collection.document("globalConfig");

      var config = await documentReference.get();
      if (config.map.containsKey(CloudConfigInfo.masterIpAddressKeyValue)) {
        _cloudConfigInfo.masterIpAddress =
            config.map[CloudConfigInfo.masterIpAddressKeyValue];
        found = true;
      }
      if (config.map.containsKey(CloudConfigInfo.masterIpPortKeyValue)) {
        _cloudConfigInfo.masterIpPort =
            config.map[CloudConfigInfo.masterIpPortKeyValue];
      }
      if (config.map.containsKey(CloudConfigInfo.backupIpAddressKeyValue)) {
        _cloudConfigInfo.backupIpAddress =
            config.map[CloudConfigInfo.backupIpAddressKeyValue];
        found = true;
      }
      if (config.map.containsKey(CloudConfigInfo.backupIpPortKeyValue)) {
        _cloudConfigInfo.backupIpPort =
            config.map[CloudConfigInfo.backupIpPortKeyValue];
      }
    } catch (e) {
      initCloudConfig();
      found = false;
    }
    return found;
  }

  init(
      {String remoteIpAddressString = HyperCubeClient.DEFAULT_SERVERIP,
      int remoteIpPort = HyperCubeClient.DEFAULT_SERVERPORT}) async {
    packetCtrl.init();
    await getCloudConfig(cloudConfigInfo);
    return super.init(
        remoteIpAddressString: cloudConfigInfo.masterIpAddress,
        remoteIpPort: cloudConfigInfo.masterIpPort);
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
