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
    @org.junit.Rule public DeviceDiagnostics diagnostics=new DeviceDiagnostics();
    @Test(timeout=450000) public void bundledTorReachesPinnedHostWithoutSeparateVpn()throws Exception{
        android.app.Instrumentation runner=InstrumentationRegistry.getInstrumentation();
        UiDevice.getInstance(runner).wakeUp();
        MainActivity activity=(MainActivity)runner.startActivitySync(new Intent(runner.getTargetContext(),MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK));
        try{
            long deadline=SystemClock.elapsedRealtime()+300000;
            while(activity.connectedOrigin().isEmpty()&&SystemClock.elapsedRealtime()<deadline)SystemClock.sleep(500);
            assertEquals("Bundled Android Tor did not reach the pinned host over the remote network",HostPolicy.ONION,activity.connectedOrigin());
            UiDevice device=UiDevice.getInstance(runner);
            java.lang.reflect.Field field=MainActivity.class.getDeclaredField("web");field.setAccessible(true);
            java.util.concurrent.atomic.AtomicReference<String> state=new java.util.concurrent.atomic.AtomicReference<>("");
            boolean rendered=false;long pageDeadline=SystemClock.elapsedRealtime()+120000;
            while(!rendered&&SystemClock.elapsedRealtime()<pageDeadline){
                runner.runOnMainSync(()->{try{android.webkit.WebView view=(android.webkit.WebView)field.get(activity);if(view!=null)view.evaluateJavascript("JSON.stringify({url:location.href,login:/sign in/i.test(document.body.innerText),text:document.body.innerText.slice(0,1200)})",state::set);}catch(Exception ignored){}});
                SystemClock.sleep(1000);
                try{org.json.JSONObject page=new org.json.JSONObject((String)new org.json.JSONTokener(state.get()).nextValue());rendered=HostPolicy.sameOrigin(HostPolicy.ONION,page.getString("url"))&&page.getBoolean("login");}catch(Exception ignored){}
            }
            System.out.println("OceanState final browser document: "+state.get());
            device.takeScreenshot(new java.io.File(runner.getTargetContext().getExternalFilesDir(null),"TunnelWebView.png"));
            device.dumpWindowHierarchy(new java.io.File(runner.getTargetContext().getExternalFilesDir(null),"TunnelWebView.xml"));
            assertTrue("Native probe succeeded but Android WebView did not render the host login page: "+state.get(),rendered);
        }finally{runner.runOnMainSync(activity::finish);}
    }
}
