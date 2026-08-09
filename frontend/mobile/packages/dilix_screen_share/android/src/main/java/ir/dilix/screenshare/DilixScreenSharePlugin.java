package ir.dilix.screenshare;

import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * روشن/خاموش‌کردنِ {@link ScreenShareService} از سمتِ Dart.
 *
 * <p>ترتیب مهم است و قابلِ جابه‌جایی نیست:
 * {@code start()} → {@code getDisplayMedia()} → … → {@code stop()}.
 * اگر سرویس بعد از گرفتنِ MediaProjection بالا بیاید، اندروید ۱۴ همان‌جا
 * SecurityException داده است.
 */
public class DilixScreenSharePlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler {

    private static final String CHANNEL = "ir.dilix/screen_share";

    private MethodChannel channel;
    private Context context;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
        // سرویس نباید از موتورِ مردهٔ Flutter جان سالم به‌در ببرد.
        stopService();
        context = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "isSupported":
                result.success(true);
                return;
            case "start": {
                if (context == null) {
                    result.error("no_context", "زمینهٔ اپ در دسترس نیست", null);
                    return;
                }
                Intent i = new Intent(context, ScreenShareService.class);
                i.putExtra(ScreenShareService.EXTRA_TITLE,
                        (String) call.argument("title"));
                i.putExtra(ScreenShareService.EXTRA_BODY,
                        (String) call.argument("body"));
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(i);
                    } else {
                        context.startService(i);
                    }
                } catch (RuntimeException e) {
                    // ForegroundServiceStartNotAllowedException وقتی اپ در
                    // پس‌زمینه است: باید به کاربر گفته شود، نه اینکه بی‌صدا
                    // بماند و getDisplayMedia بعداً crash کند.
                    result.error("start_failed", String.valueOf(e.getMessage()), null);
                    return;
                }
                result.success(true);
                return;
            }
            case "stop":
                stopService();
                result.success(true);
                return;
            default:
                result.notImplemented();
        }
    }

    private void stopService() {
        if (context == null) return;
        try {
            context.stopService(new Intent(context, ScreenShareService.class));
        } catch (RuntimeException ignored) {
            // سرویس اصلاً بالا نبود.
        }
    }
}
