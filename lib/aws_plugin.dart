import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AwsPlugin {

  final File? file;
  final String fileNameWithExt;
  final String awsFolderPath;
  final String? poolId;
  final Regions? region;
  final String bucketName;
  final String awsAccess;
  final String awsSecret;

  AwsPlugin({
    required this.fileNameWithExt,
    required this.awsFolderPath,
    required this.bucketName,
    required this.awsAccess,
    required this.awsSecret,
    this.poolId,
    this.region = Regions.US_WEST_2,
    this.file,
  });

  static const EventChannel _eventChannel =
      const EventChannel('uploading_status');

  static const MethodChannel _channel =
      const MethodChannel('com.gertech.aws_plugin');

  Future<String> get uploadFile async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("filePath", () => file?.path);
    args.putIfAbsent("awsFolder", () => awsFolderPath);
    args.putIfAbsent("fileNameWithExt", () => fileNameWithExt);
    args.putIfAbsent("region", () => region.toString());
    args.putIfAbsent("bucketName", () => bucketName);
    args.putIfAbsent("AWSSecret", () => awsSecret);
    args.putIfAbsent("AWSAccess", () => awsAccess);

    debugPrint("AwsS3Plugin: file path is: ${file?.path}");

    final String result = await _channel.invokeMethod('uploadToS3', args);

    return result;
  }

  Future<String> get getPreSignedURLOfFile async {
    try {
      Map<String, dynamic> args = <String, dynamic>{};
      args.putIfAbsent("awsFolder", () => awsFolderPath);
      args.putIfAbsent("fileNameWithExt", () => fileNameWithExt);
      args.putIfAbsent("bucketName", () => bucketName);
      args.putIfAbsent("region", () => region.toString());
      args.putIfAbsent("AWSSecret", () => awsSecret);
      args.putIfAbsent("AWSAccess", () => awsAccess);

      final String result =
          await _channel.invokeMethod('createPreSignedURL', args);

      return result;
    } catch (e) {
      print('presigned URL failed with error $e');
      return "";
    }
  }

  Stream get getUploadStatus => _eventChannel.receiveBroadcastStream();
}

enum Regions {
  GovCloud,
  US_GOV_EAST_1,
  US_EAST_1,
  US_EAST_2,
  US_WEST_1,
  US_WEST_2,

  ///Default: The default region of AWS Android SDK
  EU_WEST_1,
  EU_WEST_2,
  EU_WEST_3,
  EU_CENTRAL_1,
  EU_NORTH_1,
  AP_EAST_1,
  AP_SOUTH_1,
  AP_SOUTHEAST_1,
  AP_SOUTHEAST_2,
  AP_NORTHEAST_1,
  AP_NORTHEAST_2,
  SA_EAST_1,
  CA_CENTRAL_1,
  CN_NORTH_1,
  CN_NORTHWEST_1,
  ME_SOUTH_1
}
