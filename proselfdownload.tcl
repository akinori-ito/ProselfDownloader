package require http
package require tls
package require json
#package require pop3
#package require mime
#package require sqlite3
 
#tls::init -cafile C:/OpenSSL-Win32/certs/ca-cert.pem
#set server mail.tohoku.ac.jp
#set user 東北大ID
#set pass パスワード

#set p3 [pop3::open -socketcmd tls::socket $server $user $pass]

http::register https 443 tls::socket

#set host tubox.mail.tohoku.ac.jp
#set publicaddress {nMZQAA7IuU2AFREBwmdkpK62J0L0Lq}
set savedir $env(HOME)/Downloads

proc extractCookie {meta currentcookie} {
    upvar $currentcookie cookie
    set len [llength $meta]
    for {set i 0} {$i < $len} {incr i} {
        if {[lindex $meta $i] eq "Set-Cookie"} {
            incr i
            puts [lindex $meta $i]
            foreach pair [split [string map {{; } ;} [lindex $meta $i]] {;}] {
                dict set cookie $pair 1
            }
        } else {
            incr i
        }
    }
}

proc joinCookie {cookie} {
    return [join [dict keys $cookie] {;}]
}
 
proc downloadToDir {proself_url savedir} {
    regexp {https://(.*)/public/(.*)} $proself_url dummy host publicaddress
    set cookie {}

    array set sendheader [list Host $host User-Agent curl/7.60.0 Accept */*]

    # 1st access - get frame
    set token [http::geturl "https://$host/public/$publicaddress" -headers [array get sendheader]]
    extractCookie [http::meta $token] cookie
    set sendheader(Cookie) [joinCookie $cookie]
    http::cleanup $token
    
    # 2nd access - get JSESSIONID
    set query AD=init&publicaddress=$publicaddress
    set token [http::geturl "https://$host/proself/publicweb/publicweb_login.go?$query" -headers [array get sendheader]]
    extractCookie [http::meta $token] cookie
    set sendheader(Cookie) [joinCookie $cookie]
    http::cleanup $token
    
    # 3rd access - get filelist
    set query timezoneOffset=540&AD=list&publicaddress=$publicaddress
    set token [http::geturl "https://$host/proself/publicweb/publicweb.go?$query" -headers [array get sendheader]]
    extractCookie [http::meta $token] cookie
    set sendheader(Cookie) [joinCookie $cookie]
    
    # analyze JSON
    set fileinfo [json::json2dict [http::data $token]]
    http::cleanup $token
    set filelist [dict get $fileinfo propfind]
    set nfile [llength $filelist]
    
    # download files
    set filesavedir $savedir/$publicaddress
    catch {file mkdir $filesavedir}
    set result {}
    for {set i 0} {$i < $nfile} {incr i} {
        set nfinfo [lindex $filelist $i]
        set filename [encoding convertfrom utf-8 [dict get $nfinfo name]]
        set qname [http::formatQuery f [encoding convertfrom utf-8 [dict get $nfinfo hrefname]]]
        set qname [regsub f= $qname {}]
        set token [http::geturl "https://$host/proself/publicweb/publicweb.go/get/$publicaddress/$qname" \
                   -headers [array get sendheader]]
        set f [open $filesavedir/$filename wb]
        puts -nonewline $f [http::data $token]
        close $f
        http::cleanup $token
        lappend result [list $filename $filesavedir/$filename]
    }
    return $result
}

proc getmsg {con number} {
    set msg [pop3::retrieve $con $number]
    return [mime::initialize -string $msg]
}

proc download {} {
    global savedir tubox_url
    .result delete 1.0 end
    if {$tubox_url ne {}} {
        set res [downloadToDir $tubox_url $savedir]
        for {set i 0} {$i < [llength $res]} {incr i} {
            .result insert end [lindex $res $i 1]
            .result insert end "\n"
        }
    }
}

proc paste_url {} {
    global tubox_url
    .top.url delete 0 end
    set tubox_url [clipboard get]
}

frame .top
pack .top
label .top.l1 -text {保存フォルダ：}
entry .top.savedir -width 60 -textvariable savedir
button .top.l2 -text {TUBoxのURL：} -command paste_url
entry .top.url -width 60 -textvariable tubox_url
grid .top.l1 -row 0 -column 0
grid .top.savedir -row 0 -column 1
grid .top.l2 -row 1 -column 0
grid .top.url -row 1 -column 1
pack [frame .btn] -side top
button .btn.download -text {ダウンロード} -command download
button .btn.exit -text {終了} -command exit
pack .btn.download .btn.exit -side left
text .result -width 60 -height 5
pack .result -side top

