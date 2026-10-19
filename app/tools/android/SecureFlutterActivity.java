package __PACKAGE__;

import android.os.Bundle;
import io.flutter.embedding.android.FlutterActivity;

/** MainActivity inherits this without replacing its own engine/billing/navigation hooks. */
public class SecureFlutterActivity extends FlutterActivity {
    @Override public void onCreate(Bundle state) {
        SecureGameWindows.apply(this);
        super.onCreate(state);
        SecureGameWindows.apply(this);
    }

    @Override public void onResume() {
        super.onResume();
        SecureGameWindows.apply(this);
    }

    @Override public void onWindowFocusChanged(boolean hasFocus) {
        SecureGameWindows.apply(this);
        super.onWindowFocusChanged(hasFocus);
        SecureGameWindows.apply(this);
    }
}
