package ir.dilix.mediastore;

import android.Manifest;
import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;

import androidx.annotation.NonNull;

import java.io.Closeable;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * نوشتنِ فایل در مجموعه‌های عمومیِ MediaStore (تصویر/ویدیو/صدا/دانلود).
 *
 * <p>روی API 29+ هیچ مجوزی لازم نیست: با Scoped Storage اپ می‌تواند رکوردِ
 * *خودش* را در مجموعه‌های عمومی بسازد. روی API 23..28 مجوزِ
 * {@code WRITE_EXTERNAL_STORAGE} در زمانِ اجرا گرفته می‌شود و پیش از API 23
 * مجوز هنگامِ نصب داده شده است.
 *
 * <p>عمداً به {@code androidx.core} وابسته نیست؛ هر وابستگیِ اضافه در این ماژول
 * یک نسخهٔ دیگر است که می‌تواند با وابستگی‌های اپ تداخل کند.
 */
public class DilixMediaStorePlugin
        implements FlutterPlugin,
        MethodChannel.MethodCallHandler,
        ActivityAware,
        PluginRegistry.RequestPermissionsResultListener {

    private static final String CHANNEL = "ir.dilix/media_store";
    private static final String ALBUM = "Dilix";
    private static final int REQ_WRITE = 0x0D15;

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding activityBinding;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();

    /** درخواستِ در انتظارِ مجوز (فقط API 23..28). */
    private MethodCall pendingCall;
    private MethodChannel.Result pendingResult;

    // ─────────────── چرخهٔ عمر ───────────────

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
        context = null;
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(this);
        }
        activityBinding = null;
        activity = null;
    }

    // ─────────────── کانال ───────────────

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("isSupported".equals(call.method)) {
            result.success(true);
            return;
        }
        if (!"save".equals(call.method)) {
            result.notImplemented();
            return;
        }
        if (needsLegacyPermission()) {
            if (activity == null) {
                result.error("no_activity", "اکتیویتی در دسترس نیست", null);
                return;
            }
            // فقط یک درخواستِ در انتظار: دومی بی‌درنگ رد می‌شود، وگرنه
            // `pendingResult` بازنویسی می‌شد و اولی برای همیشه بی‌پاسخ می‌ماند.
            if (pendingResult != null) {
                result.error("busy", "درخواستِ مجوزِ دیگری در جریان است", null);
                return;
            }
            pendingCall = call;
            pendingResult = result;
            activity.requestPermissions(
                    new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, REQ_WRITE);
            return;
        }
        dispatchSave(call, result);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
                                              @NonNull int[] grantResults) {
        if (requestCode != REQ_WRITE) return false;
        MethodCall call = pendingCall;
        MethodChannel.Result result = pendingResult;
        pendingCall = null;
        pendingResult = null;
        if (result == null) return true;
        boolean granted = grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        if (granted) {
            dispatchSave(call, result);
        } else {
            result.error("permission_denied", "اجازهٔ نوشتن در حافظه داده نشد", null);
        }
        return true;
    }

    private boolean needsLegacyPermission() {
        // API 29+ : Scoped Storage، بدونِ مجوز. زیرِ API 23: مجوز هنگامِ نصب.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return false;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false;
        return context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED;
    }

    // ─────────────── ذخیره ───────────────

    private void dispatchSave(final MethodCall call, final MethodChannel.Result result) {
        final String path = call.argument("path");
        final String name = call.argument("name");
        final String mimeArg = call.argument("mime");
        if (path == null || name == null) {
            result.error("bad_args", "مسیر یا نامِ فایل خالی است", null);
            return;
        }
        // IO هرگز روی رشتهٔ اصلی: فایلِ ویدیو می‌تواند ده‌ها مگابایت باشد و کپیِ
        // همزمان دقیقاً در لحظهٔ «ذخیره» رابطِ کاربری را فریز می‌کند.
        io.execute(new Runnable() {
            @Override
            public void run() {
                try {
                    String where = write(path, safeName(name), resolveMime(mimeArg, name));
                    reply(result, where, null, null);
                } catch (Exception e) {
                    reply(result, null, "save_failed", String.valueOf(e.getMessage()));
                }
            }
        });
    }

    private void reply(final MethodChannel.Result result, final String ok,
                       final String errCode, final String errMsg) {
        main.post(new Runnable() {
            @Override
            public void run() {
                if (errCode == null) {
                    result.success(ok);
                } else {
                    result.error(errCode, errMsg, null);
                }
            }
        });
    }

    private String write(String sourcePath, String name, String mime) throws IOException {
        File source = new File(sourcePath);
        if (!source.isFile()) throw new IOException("فایلِ مبدأ وجود ندارد");
        String dir = directoryFor(mime);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return writeScoped(source, name, mime, dir);
        }
        return writeLegacy(source, name, dir);
    }

    /** API 29+ — بدونِ مجوز، با IS_PENDING تا فایلِ نیمه‌کاره در گالری دیده نشود. */
    private String writeScoped(File source, String name, String mime, String dir)
            throws IOException {
        ContentResolver cr = context.getContentResolver();
        ContentValues values = new ContentValues();
        values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
        values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
        values.put(MediaStore.MediaColumns.RELATIVE_PATH, dir + File.separator + ALBUM);
        values.put(MediaStore.MediaColumns.IS_PENDING, 1);

        Uri item = cr.insert(collectionFor(mime), values);
        if (item == null) throw new IOException("MediaStore رکوردی نساخت");
        try {
            OutputStream out = cr.openOutputStream(item);
            if (out == null) throw new IOException("جریانِ نوشتن باز نشد");
            copy(source, out);
            values.clear();
            values.put(MediaStore.MediaColumns.IS_PENDING, 0);
            cr.update(item, values, null, null);
        } catch (IOException e) {
            // رکوردِ ناقص باید برود، وگرنه یک ورودیِ خرابِ همیشگی در گالری می‌ماند.
            cr.delete(item, null, null);
            throw e;
        }
        return dir + "/" + ALBUM;
    }

    /** API ≤ 28 — نوشتنِ مستقیم در پوشهٔ عمومی + اطلاع به اسکنرِ رسانه. */
    private String writeLegacy(File source, String name, String dir) throws IOException {
        File folder = new File(Environment.getExternalStoragePublicDirectory(dir), ALBUM);
        if (!folder.isDirectory() && !folder.mkdirs()) {
            throw new IOException("ساختِ پوشه ناموفق بود");
        }
        File target = uniqueFile(folder, name);
        copy(source, new FileOutputStream(target));
        // بدونِ این، فایل روی دیسک هست ولی تا ریبوتِ بعدی در گالری دیده نمی‌شود.
        MediaScannerConnection.scanFile(
                context, new String[]{target.getAbsolutePath()}, null, null);
        return dir + "/" + ALBUM;
    }

    private static File uniqueFile(File folder, String name) {
        File f = new File(folder, name);
        if (!f.exists()) return f;
        int dot = name.lastIndexOf('.');
        String base = dot > 0 ? name.substring(0, dot) : name;
        String ext = dot > 0 ? name.substring(dot) : "";
        for (int i = 1; i < 1000; i++) {
            f = new File(folder, base + "-" + i + ext);
            if (!f.exists()) return f;
        }
        return new File(folder, base + "-" + System.currentTimeMillis() + ext);
    }

    private static void copy(File source, OutputStream out) throws IOException {
        InputStream in = new FileInputStream(source);
        try {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            out.flush();
        } finally {
            closeQuietly(in);
            closeQuietly(out);
        }
    }

    private static void closeQuietly(Closeable c) {
        try {
            c.close();
        } catch (IOException ignored) {
            // بستن شکست خورد؛ خطای نوشتن (اگر بوده) قبلاً گزارش شده است.
        }
    }

    // ─────────────── نگاشتِ نوع ───────────────

    private static Uri collectionFor(String mime) {
        if (mime.startsWith("image/")) return MediaStore.Images.Media.EXTERNAL_CONTENT_URI;
        if (mime.startsWith("video/")) return MediaStore.Video.Media.EXTERNAL_CONTENT_URI;
        if (mime.startsWith("audio/")) return MediaStore.Audio.Media.EXTERNAL_CONTENT_URI;
        // `Downloads` فقط از API 29 وجود دارد و این متد هم تنها از مسیرِ
        // writeScoped (همان نسخه‌ها) صدا زده می‌شود.
        return MediaStore.Downloads.EXTERNAL_CONTENT_URI;
    }

    private static String directoryFor(String mime) {
        if (mime.startsWith("image/")) return Environment.DIRECTORY_PICTURES;
        if (mime.startsWith("video/")) return Environment.DIRECTORY_MOVIES;
        if (mime.startsWith("audio/")) return Environment.DIRECTORY_MUSIC;
        return Environment.DIRECTORY_DOWNLOADS;
    }

    /** نوعِ اعلام‌شده مرجع است؛ اگر نبود از پسوندِ نام حدس زده می‌شود. */
    private static String resolveMime(String declared, String name) {
        if (declared != null && declared.contains("/")) return declared;
        String lower = name.toLowerCase(Locale.US);
        int dot = lower.lastIndexOf('.');
        String ext = dot >= 0 ? lower.substring(dot + 1) : "";
        switch (ext) {
            case "jpg":
            case "jpeg":
                return "image/jpeg";
            case "png":
                return "image/png";
            case "gif":
                return "image/gif";
            case "webp":
                return "image/webp";
            case "mp4":
                return "video/mp4";
            case "mov":
                return "video/quicktime";
            case "webm":
                return "video/webm";
            case "m4a":
                return "audio/mp4";
            case "mp3":
                return "audio/mpeg";
            case "ogg":
                return "audio/ogg";
            case "wav":
                return "audio/wav";
            case "pdf":
                return "application/pdf";
            default:
                return "application/octet-stream";
        }
    }

    /** جداکننده‌های مسیر در DISPLAY_NAME باعثِ ردِ insert می‌شوند. */
    private static String safeName(String name) {
        String n = name.replace('/', '_').replace('\\', '_').trim();
        if (n.isEmpty()) n = "dilix-" + System.currentTimeMillis();
        return n.length() > 120 ? n.substring(n.length() - 120) : n;
    }
}
