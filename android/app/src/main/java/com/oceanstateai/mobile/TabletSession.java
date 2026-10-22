package com.oceanstateai.mobile;

import android.app.ActivityManager;
import android.content.Context;
import android.os.*;
import android.util.DisplayMetrics;
import org.json.*;
import java.util.UUID;
import java.util.concurrent.*;

/** Capability-authenticated relay session. Pending results retry; actions never replay. */
final class TabletSession {
    interface Transport { JSONObject post(String path,JSONObject body,String credential)throws Exception; }
    interface Listener { void status(String message); void changed(); }
    private final Transport transport;
    private final Listener listener;
    private final ScheduledExecutorService tasks=Executors.newScheduledThreadPool(2);
    private final JSONObject hardware;
    volatile String id="",secret="";
    private volatile boolean active;
    private JSONObject pending;
    private int failures;
    private volatile long lastBind;
    TabletSession(Context context,Transport transport,Listener listener)throws Exception{
        this.transport=transport;this.listener=listener;
        ActivityManager.MemoryInfo memory=new ActivityManager.MemoryInfo();((ActivityManager)context.getSystemService(Context.ACTIVITY_SERVICE)).getMemoryInfo(memory);
        DisplayMetrics display=context.getResources().getDisplayMetrics();StatFs storage=new StatFs(context.getFilesDir().getAbsolutePath());
        hardware=new JSONObject().put("platform","Android").put("manufacturer",Build.MANUFACTURER).put("model",Build.MODEL).put("android_version",Build.VERSION.RELEASE).put("api_level",Build.VERSION.SDK_INT).put("cpu_cores",Runtime.getRuntime().availableProcessors()).put("cpu_abis",new JSONArray(Build.SUPPORTED_ABIS)).put("soc",Build.VERSION.SDK_INT>=31?Build.SOC_MODEL:Build.HARDWARE).put("usable_system_ram_bytes",memory.totalMem).put("storage_total_bytes",storage.getTotalBytes()).put("storage_available_bytes",storage.getAvailableBytes()).put("display_width",display.widthPixels).put("display_height",display.heightPixels).put("capabilities",new JSONArray(new String[]{"environment","windows","inspect","click","type","keys","invoke","focus","screenshot"})).put("limitations","Android UI only; no Windows commands, root shell, unattended permission grants or host control. Screen data only on request while enabled.");
    }
    void start(String token){
        tasks.execute(()->{
            try{
                if(TabletAccessibility.instance==null)throw new Exception("Enable Ocean State accessibility in Android Settings first.");
                JSONObject registration=transport.post("register",new JSONObject().put("name",Build.MANUFACTURER+" "+Build.MODEL).put("hardware",hardware),token);
                id=registration.getString("device_id");secret=registration.getString("device_token");
                transport.post("file-bind",new JSONObject().put("device_id",id).put("device_secret",secret).put("learning",false),token);
                lastBind=System.currentTimeMillis();
                active=true;TabletAccessibility.allowed=true;listener.changed();listener.status("Tablet control enabled • Stop control to disconnect");
                tasks.scheduleWithFixedDelay(this::poll,0,1500,TimeUnit.MILLISECONDS);
                tasks.scheduleWithFixedDelay(()->{if(active)try{
                    transport.post("heartbeat",new JSONObject().put("device_id",id),secret);
                    if(System.currentTimeMillis()-lastBind>30000){transport.post("file-bind",new JSONObject().put("device_id",id).put("device_secret",secret).put("learning",false),token);lastBind=System.currentTimeMillis();}
                }catch(Exception e){listener.status("Tablet connection interrupted");}},3,5,TimeUnit.SECONDS);
            }catch(Exception e){listener.status("Could not enable control. Sign in and enable Android Accessibility first.");stop();}
        });
    }
    private synchronized void poll(){
        if(!active)return;
        if(TabletAccessibility.instance==null||!TabletAccessibility.allowed){stop();return;}
        try{
            if(pending!=null){transport.post("result",pending,secret);pending=null;}
            JSONObject packet=transport.post("poll",new JSONObject().put("device_id",id),secret);failures=0;
            JSONObject job=packet.optJSONObject("job");if(job==null)return;
            long deadline=(long)(job.getDouble("deadline")*1000);String action=job.getString("action");JSONObject result;
            if(!active||System.currentTimeMillis()>=deadline)result=TabletAccessibility.fail("Control stopped or action expired.");
            else{
                listener.status(Build.MODEL+" • "+action+" • Stop control to cancel");
                try{result=action.equals("environment")?new JSONObject().put("success",true).put("hardware",hardware):TabletAccessibility.instance.perform(action,job.optJSONObject("arguments")==null?new JSONObject():job.getJSONObject("arguments"),deadline);}
                catch(Exception e){result=TabletAccessibility.fail("Android action could not complete: "+e.getClass().getSimpleName());}
            }
            pending=new JSONObject().put("device_id",id).put("job_id",job.getString("id")).put("result",result);
            transport.post("result",pending,secret);pending=null;
        }catch(Exception e){if(++failures>=3){listener.status("Tablet control stopped after connection failures.");stop();}}
    }
    boolean enabled(){return active;}
    void stop(){
        active=false;TabletAccessibility.allowed=false;String previous=id,capability=secret;id="";secret="";listener.changed();
        try{tasks.execute(()->{try{if(!previous.isEmpty())transport.post("disconnect",new JSONObject().put("device_id",previous),capability);}catch(Exception ignored){}finally{tasks.shutdownNow();}});}catch(RejectedExecutionException ignored){}
    }
}
