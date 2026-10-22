package com.oceanstateai.mobile;
import android.content.Intent;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
@RunWith(AndroidJUnit4.class)
public class MobileThemeTest {
    @org.junit.Rule public DeviceDiagnostics diagnostics=new DeviceDiagnostics();
    @Test public void themeChoicesPersistAndRender()throws Exception{
        android.app.Instrumentation runner=InstrumentationRegistry.getInstrumentation();
        MainActivity activity=(MainActivity)runner.startActivitySync(new Intent(runner.getTargetContext(),MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
        UiDevice device=UiDevice.getInstance(runner);
        UiObject picker=device.findObject(new UiSelector().description("Choose animated theme"));assertTrue(picker.waitForExists(10000));picker.click();
        UiObject matrix=device.findObject(new UiSelector().textContains("Matrix"));assertTrue(matrix.waitForExists(3000));matrix.click();
        assertEquals("matrix",runner.getTargetContext().getSharedPreferences("MainActivity",0).getString("theme",""));
        picker.click();assertTrue(device.findObject(new UiSelector().textContains("Matrix")).isChecked());
        device.takeScreenshot(new java.io.File(runner.getTargetContext().getExternalFilesDir(null),"AndroidThemes.png"));
        device.findObject(new UiSelector().textContains("Deep Ocean")).click();
        assertEquals("ocean",runner.getTargetContext().getSharedPreferences("MainActivity",0).getString("theme",""));
        runner.runOnMainSync(activity::finish);
    }
}
