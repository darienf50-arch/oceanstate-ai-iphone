package com.oceanstateai.mobile;

import java.net.URI;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.Map;

public final class HostPolicy {
    public static final String LAN="https://192.168.1.153:3243";
    public static final String ONION="https://q3fqhm3ye5dmja4qtzw77lmbta2ne6ygbfs3k44osrwemqdvcxaw5dyd.onion";
    public static final Map<String,String> PINS=Map.of(
        "192.168.1.153","81A3711EE991CE228FB696A66B916865607EEAA9146EA64DB9722A1EFA51A65E",
        "q3fqhm3ye5dmja4qtzw77lmbta2ne6ygbfs3k44osrwemqdvcxaw5dyd.onion","D650D072B6B33F22C21B14FE8EBCAA525ED2DF55DB88CC6F26E1F99990E2A358");
    public static boolean sameOrigin(String first,String second) {
        try { URI a=new URI(first),b=new URI(second);return "https".equals(a.getScheme())&&"https".equals(b.getScheme())&&a.getHost()!=null&&a.getHost().equalsIgnoreCase(b.getHost())&&port(a)==port(b)&&b.getUserInfo()==null; }
        catch(Exception e){return false;}
    }
    private static int port(URI uri){return uri.getPort()==-1?443:uri.getPort();}
    public static boolean pinned(String host,X509Certificate certificate) {
        try {
            certificate.checkValidity();String expected=PINS.get(host);if(expected==null)return false;
            byte[] digest=MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded());
            StringBuilder value=new StringBuilder();for(byte b:digest)value.append(String.format("%02X",b&255));
            return expected.equals(value.toString());
        }catch(Exception e){return false;}
    }
    private HostPolicy(){}
}
