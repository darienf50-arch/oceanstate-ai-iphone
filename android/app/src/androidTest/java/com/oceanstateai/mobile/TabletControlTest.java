package com.oceanstateai.mobile;

import android.app.UiAutomation;
import android.content.*;
import android.os.*;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.*;
import org.junit.runner.RunWith;
import org.json.*;
import static org.junit.Assert.*;

@RunWith(AndroidJUnit4.class)
public class TabletControlTest {
    private android.app.Instrumentation instrumentation;
    @Before public void prepare()throws Exception{
        instrumentation=InstrumentationRegistry.getInstrumentation();
        UiAutomation automation=instrumentation.getUiAutomation(UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
        // Test emulator only: installation does not grant this permission in production.
        try(ParcelFileDescriptor command=automation.executeShellCommand("settings put secure enabled_accessibility_services com.oceanstateai.mobile/.TabletAccessibility")){new java.io.FileInputStream(command.getFileDescriptor()).readAllBytes();}
        try(ParcelFileDescriptor command=automation.executeShellCommand("settings put secure accessibility_enabled 1")){new java.io.FileInputStream(command.getFileDescriptor()).readAllBytes();}
        Intent launch=new Intent(instrumentation.getTargetContext(),MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_CLEAR_TASK).putExtra("control-fixture",true);
        instrumentation.startActivitySync(launch);instrumentation.waitForIdleSync();
        for(int attempt=0;attempt<60&&TabletAccessibility.instance==null;attempt++)SystemClock.sleep(250);
        assertNotNull("Accessibility service did not bind in emulator",TabletAccessibility.instance);
        TabletAccessibility.allowed=true;
    }
    @After public void cleanup(){TabletAccessibility.allowed=false;}
    private JSONObject run(String action,JSONObject arguments)throws Exception{return TabletAccessibility.instance.perform(action,arguments,System.currentTimeMillis()+15000);}
    @Test public void disabledSessionsAndWindowsCommandsAreRejected()throws Exception{
        assertFalse(run("command",new JSONObject()).getBoolean("success"));
        TabletAccessibility.allowed=false;assertFalse(run("windows",new JSONObject()).getBoolean("success"));
    }
    @Test public void realAndroidInspectTypeInvokeAndScreenshot()throws Exception{
        JSONObject windows=run("windows",new JSONObject());assertTrue(windows.toString(),windows.getBoolean("success"));
        String handle=windows.getJSONArray("windows").getJSONObject(0).getString("window_handle");
        JSONObject inspected=run("inspect",new JSONObject().put("window_handle",handle));assertTrue(inspected.toString(),inspected.getBoolean("success"));
        JSONArray nodes=inspected.getJSONArray("controls");String input="",button="";
        for(int index=0;index<nodes.length();index++){JSONObject node=nodes.getJSONObject(index);if(node.optBoolean("editable"))input=node.getString("runtime_id");if(node.optString("name").equals("Verify tablet action"))button=node.getString("runtime_id");}
        assertFalse("Editable input not inspected",input.isEmpty());assertFalse("Button not inspected",button.isEmpty());
        assertTrue(run("type",new JSONObject().put("window_handle",handle).put("runtime_id",input).put("text","Android verified")).getBoolean("success"));
        assertTrue(run("invoke",new JSONObject().put("window_handle",handle).put("runtime_id",button)).getBoolean("success"));
        SystemClock.sleep(400);
        assertTrue(run("inspect",new JSONObject().put("window_handle",handle)).toString().contains("Verified: Android verified"));
        assertFalse(run("click",new JSONObject().put("window_handle","stale-window").put("x",100).put("y",100)).getBoolean("success"));
        JSONObject image=run("screenshot",new JSONObject());assertTrue(image.toString(),image.getBoolean("success"));assertTrue(image.getString("image").startsWith("/9j/"));
    }
}
