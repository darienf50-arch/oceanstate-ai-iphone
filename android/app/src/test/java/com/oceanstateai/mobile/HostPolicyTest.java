package com.oceanstateai.mobile;
import org.junit.Test;
import static org.junit.Assert.*;
public class HostPolicyTest {
    @Test public void exactOriginOnly(){assertTrue(HostPolicy.sameOrigin(HostPolicy.ONION,HostPolicy.ONION+"/api/config"));assertFalse(HostPolicy.sameOrigin(HostPolicy.ONION,"https://example.com/api/config"));assertFalse(HostPolicy.sameOrigin(HostPolicy.ONION,HostPolicy.ONION+":444/"));assertFalse(HostPolicy.sameOrigin(HostPolicy.ONION,"http://"+HostPolicy.ONION.substring(8)));}
    @Test public void userInfoRejected(){assertFalse(HostPolicy.sameOrigin(HostPolicy.LAN,"https://user@192.168.1.153:3243/"));}
    @Test public void certificatesCannotBeSubstituted()throws Exception{
        java.security.cert.CertificateFactory parser=java.security.cert.CertificateFactory.getInstance("X.509");
        java.security.cert.X509Certificate lan=(java.security.cert.X509Certificate)parser.generateCertificate(getClass().getResourceAsStream("/lan.crt"));
        java.security.cert.X509Certificate onion=(java.security.cert.X509Certificate)parser.generateCertificate(getClass().getResourceAsStream("/onion.crt"));
        assertTrue(HostPolicy.pinned("192.168.1.153",lan));assertFalse(HostPolicy.pinned("192.168.1.153",onion));assertFalse(HostPolicy.pinned("example.com",lan));
    }
}
