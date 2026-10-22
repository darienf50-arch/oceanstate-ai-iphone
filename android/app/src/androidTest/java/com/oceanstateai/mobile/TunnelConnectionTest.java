package com.oceanstateai.mobile;
import android.content.Intent;
import android.os.SystemClock;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import static org.junit.Assert.*;
@RunWith(AndroidJUnit4.class)
public class TunnelConnectionTest {
    @Test(timeout=450000) public void bundledTorReachesPinnedHostWithoutSeparateVpn()throws Exception{
        android.app.Instrumentation runner=InstrumentationRegistry.getInstrumentation();
        MainActivity activity=(MainActivity)runner.startActivitySync(new Intent(runner.getTargetContext(),MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
        try{
            long deadline=SystemClock.elapsedRealtime()+300000;
            while(activity.connectedOrigin().isEmpty()&&SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(500);
            assertEquals("Bundled Android Tor did not reach the pinned host over the remote network",HostPolicy.ONION,activity.connectedOrigin());
            UiDevice device=UiDevice.getInstance(runner);
            UiObject login=device.findObject(new UiSelector().textContains("Sign in"));
            assertTrue("Native probe succeeded but Android WebView did not render the host login page",login.waitForExists(120000));
        }finally{runner.runOnMainSync(activity::finish);}
    }
}
