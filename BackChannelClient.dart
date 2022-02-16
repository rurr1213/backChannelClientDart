import 'dart:typed_data';
import 'package:base_app/backChannelClientDart/HyperCubeClient.dart';
import '../ftlTools/Logger.dart';

class BackChannelClient extends HyperCubeClient {
  String remoteIpAddress = "192.168.1.216";
  int remoteIpPort = 5054;
  BackChannelClient(Logger logger) : super(logger);
  init(Function(Uint8List) _onHostTcpReceiveCallback,
      Function() onHostTcpCloseCallback,
      [String _remoteIpAddressString = "", int _remoteIpPort = 0]) async {
    if (_remoteIpAddressString != "") {
      remoteIpAddress = _remoteIpAddressString;
    }
    if (_remoteIpPort != 0) {
      remoteIpPort = _remoteIpPort;
    }
    return super.init(_onHostTcpReceiveCallback, onHostTcpCloseCallback,
        remoteIpAddress, remoteIpPort);
  }
}
