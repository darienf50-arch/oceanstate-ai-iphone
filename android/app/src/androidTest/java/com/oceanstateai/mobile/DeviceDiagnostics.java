package com.oceanstateai.mobile;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.UiDevice;
import org.junit.rules.TestWatcher;
import org.junit.runner.Description;
final class DeviceDiagnostics extends TestWatcher {
    @Override protected void failed(Throwable error,Description test){
        try{
            UiDevice device=UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
            java.io.ByteArrayOutputStream xml=new java.io.ByteArrayOutputStream();device.dumpWindowHierarchy(xml);System.out.println("OceanState failed-test window: "+xml.toString("UTF-8"));
            device.executeShellCommand("mkdir -p /sdcard/Download/ocean-diagnostics");
            device.executeShellCommand("screencap -p /sdcard/Download/ocean-diagnostics/"+test.getClassName().substring(test.getClassName().lastIndexOf('.')+1)+".png");
        }catch(Exception ignored){}
    }
}
