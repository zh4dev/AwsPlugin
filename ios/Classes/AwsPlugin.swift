import Flutter
import UIKit
import AWSCognito
import AWSS3
import Foundation

enum ChannelName {
    static let awsS3 = "com.gertech.aws_plugin"
    static let uploadingStatus = "uploading_status"
}

public class AwsPlugin: NSObject, FlutterPlugin {
    private var events: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: ChannelName.awsS3, binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: ChannelName.uploadingStatus, binaryMessenger: registrar.messenger())
        let instance = AwsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "uploadToS3":
            uploadFile(result: result, args: call.arguments)
        case "createPreSignedURL":
            getPreSignedURL(result: result, args: call.arguments)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func getPreSignedURL(result: @escaping FlutterResult, args: Any?) {
        guard let argsMap = args as? [String: Any],
              let awsFolder = argsMap["awsFolder"] as? String,
              let fileNameWithExt = argsMap["fileNameWithExt"] as? String,
              let bucketName = argsMap["bucketName"] as? String,
              let region = argsMap["region"] as? String,
              let access = argsMap["AWSAccess"] as? String,
              let secret = argsMap["AWSSecret"] as? String else {
            print("Did not provide required args")
            result(FlutterError(code: "UNAVAILABLE", message: "Did not provide required args", details: nil))
            return
        }

        let convertedRegion = decideRegion(region)
        let credentialsProvider = AWSStaticCredentialsProvider(accessKey: access, secretKey: secret)
        let configuration = AWSServiceConfiguration(region: convertedRegion, credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration

        let getPreSignedURLRequest = AWSS3GetPreSignedURLRequest()
        getPreSignedURLRequest.httpMethod = .GET
        getPreSignedURLRequest.key = awsFolder.isEmpty ? fileNameWithExt : "\(awsFolder)/\(fileNameWithExt)"
        getPreSignedURLRequest.bucket = bucketName
        getPreSignedURLRequest.expires = Date(timeIntervalSinceNow: 36000)

        AWSS3PreSignedURLBuilder.default().getPreSignedURL(getPreSignedURLRequest).continueWith { task in
            if let error = task.error {
                print("Error: \(error)")
                result(FlutterError(code: "FAILED TO CREATE PRE-SIGNED", message: "Error: \(error)", details: nil))
            } else if let url = task.result?.absoluteString {
                result(url)
            }
            return nil
        }
    }

    private func decideRegion(_ region: String) -> AWSRegionType {
        let reg = region.replacingOccurrences(of: "Regions.", with: "")
        switch reg {
            // Use a switch statement or a dictionary to map the region strings to AWSRegionType
            case "US_EAST_1": return .USEast1
            case "US_EAST_2": return .USEast2
            case "US_WEST_1": return .USWest1
            case "US_WEST_2": return .USWest2
            case "EU_WEST_1": return .EUWest1
            case "EU_WEST_2": return .EUWest2
            case "EU_CENTRAL_1": return .EUCentral1
            case "AP_SOUTHEAST_1": return .APSoutheast1
            case "AP_NORTHEAST_1": return .APNortheast1
            case "AP_NORTHEAST_2": return .APNortheast2
            case "AP_SOUTHEAST_2": return .APSoutheast2
            case "AP_SOUTH_1": return .APSouth1
            case "CN_NORTH_1": return .CNNorth1
            case "CA_CENTRAL_1": return .CACentral1
            case "USGovWest1": return .USGovWest1
            case "CN_NORTHWEST_1": return .CNNorthWest1
            case "EU_WEST_3": return .EUWest3
            case "US_GOV_EAST_1": return .USGovEast1
            case "EU_NORTH_1": return .EUNorth1
            case "AP_EAST_1": return .APEast1
            case "ME_SOUTH_1": return .MESouth1
            default: return .Unknown
        }
    }

    private func uploadFile(result: @escaping FlutterResult, args: Any?) {
        guard let argsMap = args as? [String: Any],
              let filePath = argsMap["filePath"] as? String,
              let awsFolder = argsMap["awsFolder"] as? String,
              let fileNameWithExt = argsMap["fileNameWithExt"] as? String,
              let bucketName = argsMap["bucketName"] as? String,
              let region = argsMap["region"] as? String,
              let accessKey = argsMap["AWSAccess"] as? String,
              let secretKey = argsMap["AWSSecret"] as? String else {
            print("Did not provide required args")
            result(FlutterError(code: "UNAVAILABLE", message: "Did not provide required args", details: nil))
            return
        }

        let credentialsProvider = AWSStaticCredentialsProvider(accessKey: accessKey, secretKey: secretKey)
        let configuration = AWSServiceConfiguration(region: decideRegion(region), credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration

        guard let imageURL = URL(string: filePath) else {
            print("Invalid file path")
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Invalid file path", details: nil))
            return
        }

        let key = awsFolder.isEmpty ? fileNameWithExt : "\(awsFolder)/\(fileNameWithExt)"
        let expression = AWSS3TransferUtilityUploadExpression()
        expression.progressBlock = { task, progress in
            print("progress \(progress.fractionCompleted)")
        }

        let completionHandler: AWSS3TransferUtilityUploadCompletionHandlerBlock = { task, error in
            if let error = error {
                print("Upload failed: \(error)")
                result(FlutterError(code: "UPLOAD_FAILED", message: "Upload failed: \(error)", details: nil))
            } else {
                print("✅ Upload succeeded")
                result(task.response?.url?.absoluteString ?? "")
            }
        }

        let transferUtility = AWSS3TransferUtility.default()
        transferUtility.uploadFile(imageURL, bucket: bucketName, key: key, contentType: "image/jpeg", expression: expression, completionHandler: completionHandler).continueWith { task in
            if let error = task.error {
                print("Upload task error: \(error)")
            }
            return nil
        }
    }
}

extension AwsPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.events = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.events = nil
        return nil
    }
}
