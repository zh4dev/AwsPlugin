package com.gertech.aws_plugin;

import android.content.Context;
import android.util.Log;
import androidx.annotation.NonNull;
import com.amazonaws.ClientConfiguration;
import com.amazonaws.mobile.client.AWSMobileClient;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferListener;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferObserver;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferState;
import com.amazonaws.mobileconnectors.s3.transferutility.TransferUtility;
import com.amazonaws.regions.Region;
import com.amazonaws.regions.Regions;
import com.amazonaws.services.s3.AmazonS3Client;
import com.amazonaws.services.s3.model.CannedAccessControlList;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.services.s3.model.GeneratePresignedUrlRequest;
import com.amazonaws.HttpMethod;
import java.io.File;
import java.net.URL;
import java.util.Calendar;
import java.util.Date;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

public class AwsPlugin implements FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private static final String TAG = "awsPlugin";
    private static final String CHANNEL = "com.gertech.aws_plugin";
    private static final String STREAM = "uploading_status";
    private static final String METHOD_CALL_UPLOAD = "uploadToS3";
    private static final String METHOD_CALL_PRESIGNED = "createPreSignedURL";
    private static final long EIGHT_HOURS_IN_MILLIS = 480 * 60000;

    private String filePath;
    private String awsFolder;
    private String fileNameWithExt;
    private String bucketName;
    private Context mContext;
    private MethodChannel methodChannel;
    private EventChannel eventChannel;
    private EventChannel.EventSink events;
    private Result parentResult;
    private AmazonS3Client s3Client;
    private TransferUtility transferUtility;

    private final ClientConfiguration clientConfiguration = new ClientConfiguration();

    public AwsPlugin() {
        clientConfiguration.setConnectionTimeout(250000);
        clientConfiguration.setSocketTimeout(250000);
    }

    public static void registerWith(PluginRegistry.Registrar registrar) {
        AwsPlugin s3Plugin = new AwsPlugin();
        s3Plugin.whenAttachedToEngine(registrar.context(), registrar.messenger());
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        whenAttachedToEngine(flutterPluginBinding.getApplicationContext(), flutterPluginBinding.getBinaryMessenger());
    }

    private void whenAttachedToEngine(Context applicationContext, BinaryMessenger messenger) {
        this.mContext = applicationContext;
        methodChannel = new MethodChannel(messenger, CHANNEL);
        eventChannel = new EventChannel(messenger, STREAM);
        eventChannel.setStreamHandler(this);
        methodChannel.setMethodCallHandler(this);
        Log.d(TAG, "whenAttachedToEngine");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        mContext = null;
        methodChannel.setMethodCallHandler(null);
        methodChannel = null;
        eventChannel.setStreamHandler(null);
        eventChannel = null;
        Log.d(TAG, "onDetachedFromEngine");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        parentResult = result;
        String awsAccess = call.argument("AWSAccess");
        String awsSecret = call.argument("AWSSecret");
        filePath = call.argument("filePath");
        awsFolder = call.argument("awsFolder");
        fileNameWithExt = call.argument("fileNameWithExt");
        bucketName = call.argument("bucketName");

        if (s3Client == null && awsAccess != null && awsSecret != null) {
            BasicAWSCredentials awsCreds = new BasicAWSCredentials(awsAccess, awsSecret);
            s3Client = new AmazonS3Client(awsCreds, clientConfiguration);
        }

        switch (call.method) {
            case METHOD_CALL_UPLOAD:
                setupTransferUtility();
                sendImage();
                break;
            case METHOD_CALL_PRESIGNED:
                generatePreSignedUrl(call, result);
                break;
            default:
                result.notImplemented();
        }
    }

    private void setupTransferUtility() {
        if (transferUtility == null) {
            transferUtility = TransferUtility.builder()
                    .context(mContext)
                    .awsConfiguration(AWSMobileClient.getInstance().getConfiguration())
                    .s3Client(s3Client)
                    .build();
        }
    }

    private void generatePreSignedUrl(@NonNull MethodCall call, @NonNull Result result) {
        String region = call.argument("region");
        String objectKey = awsFolder != null && !awsFolder.isEmpty() ? awsFolder + "/" + fileNameWithExt : fileNameWithExt;

        try {
            Regions awsRegion = Regions.valueOf(region != null ? region.replaceFirst("Regions.", "") : null);
            s3Client.setRegion(Region.getRegion(awsRegion));

            Calendar calendar = Calendar.getInstance();
            Date expiration = new Date(calendar.getTimeInMillis() + EIGHT_HOURS_IN_MILLIS);

            GeneratePresignedUrlRequest request = new GeneratePresignedUrlRequest(bucketName, objectKey)
                    .withMethod(HttpMethod.GET)
                    .withExpiration(expiration);

            URL preSignedUrl = s3Client.generatePresignedUrl(request);
            result.success(preSignedUrl.toString());
        } catch (Exception e) {
            Log.e(TAG, "Error generating presigned URL: ", e);
            result.success(null);
        }
    }

    private void sendImage() {
        String awsPath = awsFolder != null && !awsFolder.isEmpty() ? awsFolder + "/" + fileNameWithExt : fileNameWithExt;
        Log.d(TAG, "Uploading file: " + awsPath);

        TransferObserver observer = transferUtility.upload(bucketName, awsPath, new File(filePath), CannedAccessControlList.Private);
        observer.setTransferListener(new UploadTransferListener());
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        this.events = events;
    }

    @Override
    public void onCancel(Object arguments) {
        invalidateEventSink();
    }

    private void invalidateEventSink() {
        if (events != null) {
            events.endOfStream();
            events = null;
        }
    }

    private class UploadTransferListener implements TransferListener {
        @Override
        public void onStateChanged(int id, TransferState state) {
            switch (state) {
                case COMPLETED:
                    parentResult.success(fileNameWithExt);
                    break;
                case FAILED:
                    Log.e(TAG, "Upload failed: " + fileNameWithExt);
                    parentResult.success(null);
                    break;
                default:
                    Log.d(TAG, "Transfer state: " + state + ", file: " + fileNameWithExt);
            }
        }

        @Override
        public void onProgressChanged(int id, long bytesCurrent, long bytesTotal) {
            if (events != null) {
                int progress = (int) ((float) bytesCurrent / bytesTotal * 100);
                events.success(progress);
            }
        }

        @Override
        public void onError(int id, Exception ex) {
            Log.e(TAG, "Error during upload: ", ex);
            invalidateEventSink();
        }
    }
}
