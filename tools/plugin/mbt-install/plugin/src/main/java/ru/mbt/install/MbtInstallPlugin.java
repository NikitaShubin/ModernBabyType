package ru.mbt.install;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;

/**
 * Нативный мост для ModernBabyType: установка APK и шаринг файлов.
 * GDScript не умеет ни того, ни другого (нет FileProvider и интентов),
 * поэтому два тонких метода здесь, вся логика — в update.gd / меню.
 */
public class MbtInstallPlugin extends GodotPlugin {
	private static final String TAG = "MbtInstall";

	public MbtInstallPlugin(Godot godot) {
		super(godot);
	}

	@NonNull
	@Override
	public String getPluginName() {
		return "MbtInstall";
	}

	private Uri uriFor(String path) {
		Activity activity = getActivity();
		if (activity == null) {
			Log.e(TAG, "no activity");
			return null;
		}
		File file = new File(path);
		if (!file.exists()) {
			Log.e(TAG, "no file: " + path);
			return null;
		}
		String authority = activity.getPackageName() + ".fileprovider";
		return FileProvider.getUriForFile(activity, authority, file);
	}

	/**
	 * Открыть системный установщик для APK. Дальше — штатный диалог
	 * «Установить» (молча ставить нельзя — защита Android). Требуется
	 * REQUEST_INSTALL_PACKAGES + разовое разрешение пользователя.
	 */
	@UsedByGodot
	public void installApk(String path) {
		Activity activity = getActivity();
		Uri uri = uriFor(path);
		if (activity == null || uri == null) {
			return;
		}
		Intent intent = new Intent(Intent.ACTION_VIEW);
		intent.setDataAndType(uri, "application/vnd.android.package-archive");
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_GRANT_READ_URI_PERMISSION);
		try {
			activity.startActivity(intent);
		} catch (Exception e) {
			Log.e(TAG, "install failed: " + e);
		}
	}

	/**
	 * Поделиться файлом (лог!) через системное окно: мессенджер, почта.
	 */
	@UsedByGodot
	public void shareFile(String path, String mime) {
		Activity activity = getActivity();
		Uri uri = uriFor(path);
		if (activity == null || uri == null) {
			return;
		}
		Intent intent = new Intent(Intent.ACTION_SEND);
		intent.setType(mime == null || mime.isEmpty() ? "text/plain" : mime);
		intent.putExtra(Intent.EXTRA_STREAM, uri);
		intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
		try {
			activity.startActivity(Intent.createChooser(intent, "Поделиться"));
		} catch (Exception e) {
			Log.e(TAG, "share failed: " + e);
		}
	}
}
