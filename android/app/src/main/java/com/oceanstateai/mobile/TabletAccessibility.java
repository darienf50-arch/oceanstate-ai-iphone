package com.oceanstateai.mobile;

import android.accessibilityservice.*;
import android.content.*;
import android.graphics.*;
import android.hardware.HardwareBuffer;
import android.os.*;
import android.util.Base64;
import android.view.Display;
import android.view.accessibility.*;
import org.json.*;
import java.io.ByteArrayOutputStream;
import java.util.*;
import java.util.concurrent.*;

/** No passive collection. All reads and gestures require an enabled live session. */
public final class TabletAccessibility extends AccessibilityService {
    static volatile TabletAccessibility instance;
    static volatile boolean allowed;
    private final Map<String,AccessibilityNodeInfo> nodes=new HashMap<>();
    @Override protected void onServiceConnected(){instance=this;}
    @Override public void onAccessibilityEvent(AccessibilityEvent event){} // Never retain event/keyboard contents.
    @Override public void onInterrupt(){allowed=false;}
    @Override public void onDestroy(){allowed=false;instance=null;clearNodes();super.onDestroy();}
    private void clearNodes(){for(AccessibilityNodeInfo node:nodes.values())node.recycle();nodes.clear();}
    private String handle(AccessibilityNodeInfo root){return "android-active:"+root.getWindowId()+":"+root.getPackageName();}
    private void requireWindow(AccessibilityNodeInfo root,JSONObject args)throws Exception{
        if(!handle(root).equals(args.optString("window_handle")))throw new Exception("Inspect the current Android window and use its exact window_handle; foreground app changed or no observed handle supplied.");
    }
    static JSONObject fail(String message){try{return new JSONObject().put("success",false).put("error",message);}catch(JSONException e){throw new IllegalStateException(e);}}
    JSONObject perform(String action,JSONObject args,long deadline)throws Exception{
        if(!allowed||instance!=this||System.currentTimeMillis()>=deadline)return fail("Tablet control is disabled or this action expired.");
        if(action.equals("command"))return fail("This is Android, not Windows. No PowerShell, unrestricted shell, root access or host command fallback. Use inspected Android UI controls.");
        if(action.equals("screenshot"))return screenshot(deadline);
        CompletableFuture<JSONObject> result=new CompletableFuture<>();
        getMainExecutor().execute(()->{
            try{
                if(!allowed||System.currentTimeMillis()>=deadline){result.complete(fail("Control stopped or action expired."));return;}
                AccessibilityNodeInfo root=getRootInActiveWindow();
                if(root==null){result.complete(fail("No accessible active window. Unlock the tablet locally; protected screens cannot be read."));return;}
                try{
                    String current=handle(root);
                    if(action.equals("windows")){result.complete(new JSONObject().put("success",true).put("windows",new JSONArray().put(new JSONObject().put("window_handle",current).put("package",String.valueOf(root.getPackageName())).put("platform","Android"))));return;}
                    requireWindow(root,args);
                    if(action.equals("inspect")){
                        clearNodes();JSONArray controls=new JSONArray();collect(root,controls,0);
                        result.complete(new JSONObject().put("success",true).put("window_handle",current).put("controls",controls).put("note","Visible accessibility data only; password text omitted. Node IDs are valid only for this inspected window. Reinspect after changes."));return;
                    }
                    if(action.equals("keys")){
                        String key=args.optString("text",args.optString("keys","")).toUpperCase(Locale.ROOT).replace("{","").replace("}","");
                        int global=key.equals("BACK")||key.equals("ESC")?GLOBAL_ACTION_BACK:key.equals("HOME")?GLOBAL_ACTION_HOME:key.equals("RECENTS")?GLOBAL_ACTION_RECENTS:0;
                        if(global!=0){result.complete(new JSONObject().put("success",performGlobalAction(global)).put("action",key));return;}
                        AccessibilityNodeInfo focused=root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
                        boolean okay=key.equals("ENTER")&&focused!=null&&focused.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.getId());if(focused!=null)focused.recycle();
                        result.complete(new JSONObject().put("success",okay).put("supported_keys","BACK, HOME, RECENTS, ENTER"));return;
                    }
                    if(action.equals("click")){
                        float x=(float)args.optDouble("x",-1),y=(float)args.optDouble("y",-1);Rect bounds=new Rect();root.getBoundsInScreen(bounds);
                        if(!bounds.contains((int)x,(int)y))throw new Exception("Click is outside the observed active window.");
                        Path path=new Path();path.moveTo(x,y);GestureDescription gesture=new GestureDescription.Builder().addStroke(new GestureDescription.StrokeDescription(path,0,90)).build();
                        boolean submitted=dispatchGesture(gesture,new GestureResultCallback(){@Override public void onCompleted(GestureDescription g){result.complete(success("tap"));}@Override public void onCancelled(GestureDescription g){result.complete(fail("Tap was cancelled."));}},null);
                        if(!submitted)result.complete(fail("Android rejected the gesture."));return;
                    }
                    AccessibilityNodeInfo selected=null;
                    String id=args.optString("runtime_id","");if(!id.isEmpty())selected=nodes.get(id);
                    if(selected==null&&args.has("name")){
                        for(AccessibilityNodeInfo node:nodes.values())if(!node.isPassword()&&args.optString("name").equals(String.valueOf(node.getText()))){if(selected!=null)throw new Exception("More than one control matches. Use an inspected runtime_id.");selected=node;}
                    }
                    boolean owned=false;
                    if(selected==null&&action.equals("type")){selected=root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);owned=true;}
                    if(selected==null)throw new Exception("Inspect first and choose a visible runtime_id, or focus an editable field before typing.");
                    try{
                        if(!selected.refresh()||selected.getWindowId()!=root.getWindowId()||!selected.isVisibleToUser())throw new Exception("Control is stale; inspect the active window again.");
                        if(selected.isPassword())throw new Exception("Enter protected credentials locally on the tablet.");
                        boolean okay;
                        if(action.equals("type")){if(!selected.isEditable())throw new Exception("Target is not an editable field.");Bundle value=new Bundle();value.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,args.optString("text"));okay=selected.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,value);}
                        else if(action.equals("invoke"))okay=selected.performAction(AccessibilityNodeInfo.ACTION_CLICK);
                        else if(action.equals("focus"))okay=selected.performAction(AccessibilityNodeInfo.ACTION_FOCUS);
                        else throw new Exception("Unsupported Android action. Use environment, windows, inspect, click, type, keys, invoke, focus or screenshot.");
                        result.complete(new JSONObject().put("success",okay).put("action",action));
                    }finally{if(owned)selected.recycle();}
                }finally{root.recycle();}
            }catch(Exception e){result.complete(fail(e.getMessage()));}
        });
        return result.get(Math.max(1,Math.min(12_000,deadline-System.currentTimeMillis())),TimeUnit.MILLISECONDS);
    }
    private JSONObject success(String action){try{return new JSONObject().put("success",true).put("action",action);}catch(Exception e){return fail("Could not format the result.");}}
    private void collect(AccessibilityNodeInfo node,JSONArray list,int depth)throws Exception{
        if(depth>20||list.length()>=250)return;
        if(node.isVisibleToUser()){
            String id="node-"+nodes.size();nodes.put(id,AccessibilityNodeInfo.obtain(node));Rect bounds=new Rect();node.getBoundsInScreen(bounds);
            list.put(new JSONObject().put("runtime_id",id).put("class",String.valueOf(node.getClassName())).put("name",node.isPassword()?"[protected field]":String.valueOf(node.getText())).put("description",node.isPassword()?"":String.valueOf(node.getContentDescription())).put("clickable",node.isClickable()).put("editable",node.isEditable()).put("rect",new JSONArray(new int[]{bounds.left,bounds.top,bounds.right,bounds.bottom})));
        }
        for(int index=0;index<node.getChildCount()&&list.length()<250;index++){AccessibilityNodeInfo child=node.getChild(index);if(child!=null){try{collect(child,list,depth+1);}finally{child.recycle();}}}
    }
    private JSONObject screenshot(long deadline)throws Exception{
        CompletableFuture<JSONObject> result=new CompletableFuture<>();
        getMainExecutor().execute(()->{
            if(!allowed||System.currentTimeMillis()>=deadline){result.complete(fail("Control stopped or action expired."));return;}
            takeScreenshot(Display.DEFAULT_DISPLAY,getMainExecutor(),new TakeScreenshotCallback(){
                @Override public void onFailure(int error){result.complete(fail("Android denied screen capture (protected screen or rate limit). Error "+error));}
                @Override public void onSuccess(ScreenshotResult image){
                    try(HardwareBuffer buffer=image.getHardwareBuffer()){
                        if(!allowed){result.complete(fail("Control stopped."));return;}
                        Bitmap hardware=Bitmap.wrapHardwareBuffer(buffer,image.getColorSpace());if(hardware==null)throw new Exception("No readable screen.");
                        int width=hardware.getWidth(),height=hardware.getHeight();float scale=Math.min(1f,1280f/Math.max(width,height));
                        Bitmap software=hardware.copy(Bitmap.Config.ARGB_8888,false);hardware.recycle();Bitmap scaled=Bitmap.createScaledBitmap(software,Math.max(1,Math.round(width*scale)),Math.max(1,Math.round(height*scale)),true);
                        ByteArrayOutputStream bytes=new ByteArrayOutputStream();scaled.compress(Bitmap.CompressFormat.JPEG,70,bytes);if(scaled!=software)scaled.recycle();software.recycle();
                        result.complete(new JSONObject().put("success",true).put("image",Base64.encodeToString(bytes.toByteArray(),Base64.NO_WRAP)).put("width",width).put("height",height).put("scale",scale).put("note","On-demand Android display capture. Coordinate actions use original physical pixels, not the resized preview."));
                    }catch(Exception e){result.complete(fail("Screen capture unavailable."));}
                }
            });
        });
        return result.get(Math.max(1,Math.min(12000,deadline-System.currentTimeMillis())),TimeUnit.MILLISECONDS);
    }
}
