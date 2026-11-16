package br.paginas.app;

import android.Manifest;
import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.Calendar;
import java.util.List;
import java.util.Map;
import java.util.Random;

/** Notificações de reflexão: agendadas pelo app (Ajustes > Reflexões), funcionam com o app fechado. */
public class Reflexoes extends BroadcastReceiver {
    static final String ACAO = "br.paginas.app.REFLEXAO", ACAO_LEMB = "br.paginas.app.LEMBRETE", CANAL = "reflexoes", CANAL_LEMB = "lembrete", PREFS = "reflexoes";

    @Override
    public void onReceive(Context ctx, Intent i) {
        String a = i == null ? null : i.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(a) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) {
            agendar(ctx, ctx.getSharedPreferences(PREFS, 0).getString("cfg", "{}"));
            agendarLembrete(ctx, ctx.getSharedPreferences(PREFS, 0).getString("lemb", "{}"));
        } else if (ACAO.equals(a)) {
            mostrar(ctx);
        } else if (ACAO_LEMB.equals(a)) {
            lembrete(ctx, false);
        }
    }

    /** cfg = {"on":true,"horas":["09:00","20:00"]} */
    static void agendar(Context ctx, String cfg) {
        SharedPreferences sp = ctx.getSharedPreferences(PREFS, 0);
        sp.edit().putString("cfg", cfg == null ? "{}" : cfg).apply();
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        for (int k = 0; k < 3; k++) am.cancel(pendente(ctx, k));
        try {
            Object o = Servidor.Json.ler(cfg);
            if (!(o instanceof Map)) return;
            Map<?, ?> m = (Map<?, ?>) o;
            if (!Boolean.TRUE.equals(m.get("on")) || !(m.get("horas") instanceof List)) return;
            List<?> horas = (List<?>) m.get("horas");
            for (int k = 0; k < Math.min(3, horas.size()); k++) {
                String[] hm = String.valueOf(horas.get(k)).split(":");
                if (hm.length != 2) continue;
                Calendar c = Calendar.getInstance();
                c.set(Calendar.HOUR_OF_DAY, Integer.parseInt(hm[0].trim()));
                c.set(Calendar.MINUTE, Integer.parseInt(hm[1].trim()));
                c.set(Calendar.SECOND, 0);
                c.set(Calendar.MILLISECOND, 0);
                if (c.getTimeInMillis() <= System.currentTimeMillis() + 30000) c.add(Calendar.DAY_OF_YEAR, 1);
                am.setInexactRepeating(AlarmManager.RTC_WAKEUP, c.getTimeInMillis(), AlarmManager.INTERVAL_DAY, pendente(ctx, k));
            }
        } catch (Exception e) { Log.w("Paginas", "reflexoes", e); }
    }

    /** Lembrete de leitura: cfg = {"on":true,"hora":"20:00"}. Só avisa se a pessoa ainda não leu no dia. */
    static void agendarLembrete(Context ctx, String cfg) {
        ctx.getSharedPreferences(PREFS, 0).edit().putString("lemb", cfg == null ? "{}" : cfg).apply();
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        PendingIntent pi = pendenteLemb(ctx);
        am.cancel(pi);
        try {
            Object o = Servidor.Json.ler(cfg);
            if (!(o instanceof Map)) return;
            Map<?, ?> m = (Map<?, ?>) o;
            if (!Boolean.TRUE.equals(m.get("on"))) return;
            String[] hm = String.valueOf(m.get("hora")).split(":");
            if (hm.length != 2) return;
            Calendar c = Calendar.getInstance();
            c.set(Calendar.HOUR_OF_DAY, Integer.parseInt(hm[0].trim()));
            c.set(Calendar.MINUTE, Integer.parseInt(hm[1].trim()));
            c.set(Calendar.SECOND, 0);
            c.set(Calendar.MILLISECOND, 0);
            if (c.getTimeInMillis() <= System.currentTimeMillis() + 30000) c.add(Calendar.DAY_OF_YEAR, 1);
            am.setInexactRepeating(AlarmManager.RTC_WAKEUP, c.getTimeInMillis(), AlarmManager.INTERVAL_DAY, pi);
        } catch (Exception e) { Log.w("Paginas", "lembrete", e); }
    }

    static PendingIntent pendenteLemb(Context ctx) {
        Intent i = new Intent(ctx, Reflexoes.class).setAction(ACAO_LEMB);
        return PendingIntent.getBroadcast(ctx, 200, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static String txt(Object o) { return o == null ? "" : String.valueOf(o); }

    /** Mostra o lembrete de leitura (forcar = teste, mostra mesmo se já leu hoje). */
    static void lembrete(Context ctx, boolean forcar) {
        try {
            if (Build.VERSION.SDK_INT >= 33 && ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return;
            Map<?, ?> info = null;
            java.io.File f = new java.io.File(ctx.getFilesDir(), "dados.json");
            if (f.exists()) {
                try (InputStream is = new java.io.FileInputStream(f)) {
                    ByteArrayOutputStream b = new ByteArrayOutputStream();
                    byte[] buf = new byte[65536];
                    int n;
                    while ((n = is.read(buf)) > 0) b.write(buf, 0, n);
                    Object o = Servidor.Json.ler(b.toString("UTF-8"));
                    if (o instanceof Map && ((Map<?, ?>) o).get("lembInfo") instanceof Map) info = (Map<?, ?>) ((Map<?, ?>) o).get("lembInfo");
                }
            }
            java.text.SimpleDateFormat df = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT);
            Calendar c = Calendar.getInstance();
            String hoje = df.format(c.getTime());
            c.add(Calendar.DAY_OF_YEAR, -1);
            String ontem = df.format(c.getTime());
            String feito = info == null ? "" : txt(info.get("feito"));
            if (!forcar && hoje.equals(feito)) return;   // já leu hoje: não incomoda
            int seq = 0;
            try { seq = (int) Double.parseDouble(txt(info == null ? null : info.get("seq"))); } catch (Exception e) { }
            String meta = info == null ? "15" : txt(info.get("meta")).replaceAll("\\.0$", "");
            String un = info == null ? "minutos" : txt(info.get("un"));
            String livro = info == null ? "" : txt(info.get("livro"));
            String titulo, corpo;
            if (seq > 0 && ontem.equals(feito)) {
                titulo = "Sua sequência de " + seq + (seq == 1 ? " dia" : " dias") + " está esperando 🔥";
                corpo = "Leia " + meta + " " + un + " hoje para não perder o fogo.";
            } else {
                titulo = "Hora de ler 📖";
                corpo = "Que tal " + meta + " " + un + " de leitura agora? Um pouquinho por dia vira hábito.";
            }
            if (!livro.isEmpty()) corpo += " Continue “" + livro + "”.";
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            nm.createNotificationChannel(new NotificationChannel(CANAL_LEMB, "Lembrete de leitura", NotificationManager.IMPORTANCE_HIGH));
            Intent abrir = new Intent(ctx, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(ctx, 1, abrir, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            Notification nt = new Notification.Builder(ctx, CANAL_LEMB)
                    .setSmallIcon(R.drawable.ic_notif)
                    .setColor(0xFFB4532A)
                    .setContentTitle(titulo)
                    .setContentText(corpo)
                    .setStyle(new Notification.BigTextStyle().bigText(corpo))
                    .setContentIntent(pi)
                    .setAutoCancel(true)
                    .build();
            nm.notify(8, nt);
        } catch (Exception e) { Log.w("Paginas", "lembrete", e); }
    }

    static PendingIntent pendente(Context ctx, int k) {
        Intent i = new Intent(ctx, Reflexoes.class).setAction(ACAO);
        return PendingIntent.getBroadcast(ctx, 100 + k, i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    static void mostrar(Context ctx) {
        try {
            if (Build.VERSION.SDK_INT >= 33 && ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return;
            String t = "Leia um pouco hoje. Uma página já conta.", a = "";
            try (InputStream is = ctx.getAssets().open("reflexoes.json")) {
                ByteArrayOutputStream b = new ByteArrayOutputStream();
                byte[] buf = new byte[8192];
                int n;
                while ((n = is.read(buf)) > 0) b.write(buf, 0, n);
                Object o = Servidor.Json.ler(b.toString("UTF-8"));
                if (o instanceof List && !((List<?>) o).isEmpty()) {
                    List<?> l = (List<?>) o;
                    Object r = l.get(new Random().nextInt(l.size()));
                    if (r instanceof Map) { t = String.valueOf(((Map<?, ?>) r).get("t")); Object x = ((Map<?, ?>) r).get("a"); a = x == null ? "" : String.valueOf(x); }
                }
            }
            NotificationManager nm = (NotificationManager) ctx.getSystemService(Context.NOTIFICATION_SERVICE);
            if (nm == null) return;
            nm.createNotificationChannel(new NotificationChannel(CANAL, "Reflexões", NotificationManager.IMPORTANCE_DEFAULT));
            Intent abrir = new Intent(ctx, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(ctx, 0, abrir, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            String corpo = a.isEmpty() ? t : t + "\n— " + a;
            Notification nt = new Notification.Builder(ctx, CANAL)
                    .setSmallIcon(R.drawable.ic_notif)
                    .setColor(0xFFB4532A)
                    .setContentTitle("Reflexão do Páginas 💭")
                    .setContentText(t)
                    .setStyle(new Notification.BigTextStyle().bigText(corpo))
                    .setContentIntent(pi)
                    .setAutoCancel(true)
                    .build();
            nm.notify(7, nt);
        } catch (Exception e) { Log.w("Paginas", "reflexao", e); }
    }
}
