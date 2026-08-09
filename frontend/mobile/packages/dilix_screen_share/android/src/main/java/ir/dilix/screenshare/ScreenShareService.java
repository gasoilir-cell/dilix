package ir.dilix.screenshare;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/**
 * سرویسِ پیش‌زمینهٔ نوعِ {@code mediaProjection}.
 *
 * <p>تنها کارش «زنده بودن» است. از اندروید ۱۴ (API 34) فراخوانیِ
 * {@code MediaProjectionManager.getMediaProjection()} وقتی اپ سرویسِ
 * پیش‌زمینه‌ای با این نوع در حالِ اجرا ندارد، {@link SecurityException} می‌دهد.
 * پس باید <b>پیش از</b> {@code getDisplayMedia} بالا بیاید و پس از توقفِ
 * اشتراک خاموش شود — نگه‌داشتنش اعلانِ همیشگی و مصرفِ باتری است.
 *
 * <p>عمداً بدونِ {@code androidx.core}: {@code NotificationCompat} فقط برای
 * ساختنِ یک اعلانِ ساده یک وابستگیِ دیگر به اپ اضافه می‌کند.
 */
public class ScreenShareService extends Service {

    private static final String CHANNEL_ID = "dilix_screen_share";
    private static final int NOTIFICATION_ID = 0x5C41;

    /** متنِ اعلان از سمتِ Dart می‌آید تا با زبانِ فعالِ اپ هم‌خوان باشد. */
    static final String EXTRA_TITLE = "title";
    static final String EXTRA_BODY = "body";

    @Override
    public IBinder onBind(Intent intent) {
        return null;   // سرویسِ started است، نه bound
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String title = intent != null ? intent.getStringExtra(EXTRA_TITLE) : null;
        String body = intent != null ? intent.getStringExtra(EXTRA_BODY) : null;
        if (title == null || title.isEmpty()) title = "Dilix";
        if (body == null || body.isEmpty()) body = "Screen sharing is active";

        createChannel();
        Notification n = buildNotification(title, body);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, n,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, n,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION);
        } else {
            startForeground(NOTIFICATION_ID, n);
        }
        // اگر سیستم سرویس را کشت، خودکار برنگردد: بدونِ MediaProjectionِ زنده
        // بی‌معنی است و فقط یک اعلانِ سرگردان می‌سازد.
        return START_NOT_STICKY;
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = (NotificationManager)
                getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null || nm.getNotificationChannel(CHANNEL_ID) != null) return;
        NotificationChannel ch = new NotificationChannel(
                CHANNEL_ID, "Screen sharing", NotificationManager.IMPORTANCE_LOW);
        ch.setShowBadge(false);
        nm.createNotificationChannel(ch);
    }

    @SuppressWarnings("deprecation")   // Notification.Builder() پیش از API 26
    private Notification buildNotification(String title, String body) {
        Notification.Builder b;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            b = new Notification.Builder(this, CHANNEL_ID);
        } else {
            b = new Notification.Builder(this);
        }
        return b.setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_menu_share)
                .setOngoing(true)
                .build();
    }
}
