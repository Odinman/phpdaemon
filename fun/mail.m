<?php
/*
  +----------------------------------------------------------------------+
  | Name:fun/fun.mail.m                                                  |
  +----------------------------------------------------------------------+
  | Comment:发送邮件相关函数                                             |
  +----------------------------------------------------------------------+
  | Author:Odin                                                          |
  +----------------------------------------------------------------------+
  | Create:2010-01-08 17:53:50                                           |
  +----------------------------------------------------------------------+
  | Last-Modified:2010-01-08 17:53:59                                    |
  +----------------------------------------------------------------------+
*/

/* 邮件头编码 */
function mailHeaderEncode($header,$charset='UTF-8') {
    if (!empty($header)) {
        return "=?".$charset."?B?".base64_encode($header)."?=";
    } else {
        return null;
    }
}

/* sendmail 方式发送邮件 */
function sendMail($message,$subject,$addrs,$fromuser="system",$sysuser='madreport',$sysutil="/usr/sbin/sendmail -t",$contenttype="text/plain; charset=\"utf-8\""){
    foreach ((array)$addrs as $addr) {
        $messages ="To: $addr\n";
        $messages.="From: ".mailHeaderEncode($fromuser)." <$sysuser@localhost>\n";
        $messages.="Subject: ".mailHeaderEncode($subject)."\n";
        $messages.="MIME-version: 1.0\n";
        $messages.="Content-Type: $contenttype\n\n";
        $messages.=$message;
        echo $messages."\n";
        //system("echo '$message' | /usr/bin/mail -s '$subject' $addr -sendmail-option -F'$fromuser'",$stat);
        $command="echo '$messages' | $sysutil";
        system($command,$stat);
    }
    return $stat;
}

/* 可以发送附件 */
function sendMultipartMail($message,$subject,$addr,$fromuser="system",$attachfile=null,$attachtype='text/plain',$sysuser='madreport',$sysutil="/usr/sbin/sendmail -t") {
    $preamble1= "".
        "        This message is in MIME format.  But if you can see this,\n".
        "        you aren't using a MIME aware mail program.  You shouldn't\n".
        "        have too many problems because this message is entirely in\n".
        "        ASCII and is designed to be somewhat readable with old\n".
        "        mail software.\n\n";
    $preamble2= "\n".
        "        This message is in MIME format.  But if you can see this,\n".
        "        you aren't using a MIME aware mail program.  Some parts of\n".
        "        of this message have been uuencoded for transport.  On a Unix\n".
        "        system, the program uudecode should be used to restore the file.\n\n";
    if (!empty($attachfile) && file_exists($attachfile) && !is_dir($attachfile)) {
        $with_attach=true;
        $attachtype=($attachtype=='text/plain')?'text/plain':'application/octet-stream';
        $filename=basename($attachfile);
    }

    $body.="From: ".mailHeaderEncode($fromuser)." <$sysuser@localhost>\n";
    $body.="To: $addr\n";
    $body.="Subject: ".mailHeaderEncode($subject)."\n";
    $body.="X-Mailer: MadPHPSender1.0\n";
    $body.="MIME-version: 1.0\n";
    if ($with_attach) {
        $body.="Content-Type: multipart/mixed;\n";
        $body.="    boundary=\"=== This is the boundary between parts of the message. ===--\"\n\n";
        if ($attachtype!='text/plain') {
            $body.=$preamble1;
        } else {
            $body.=$preamble2;
        }
        $body.="--=== This is the boundary between parts of the message. ===--\n";
    }
    $body.="Content-Type: text/plain; charset=\"utf-8\"\n\n";
    $body.=$message."\n";
    if ($with_attach) {
        $tmp_file='/tmp/madsender.tmp';
        $fp=@fopen($tmp_file,"wb");
        fputs($fp,$body);

        fputs($fp,"--=== This is the boundary between parts of the message. ===--\n");
        fputs($fp,"Content-Type: $attachtype; name=\"$filename\"\n");
        if ($attachtype!='text/plain') {
            fputs($fp,"Content-Transfer-Encoding: x-uue\n");
        }
        fputs($fp,"Content-Disposition: attachment; filename=\"$filename\"\n\n");
        if ($attachtype!='text/plain') {
            @exec("/bin/cat $attachfile | /usr/bin/uuencode $filename",$output); //编码
            if (!empty($output)) {
                foreach ($output as $line) {
                    fputs($fp,$line."\n");
                }
            }
        } else {
            @exec("/bin/cat $attachfile",$output);
            if (!empty($output)) {
                foreach ($output as $line) {
                    fputs($fp,$line."\n");
                }
            }
        }

        fputs($fp,"\n--=== This is the boundary between parts of the message. ===----");
        fclose($fp);

        $command="/bin/cat $tmp_file | $sysutil";
    } else {
        $command="echo '$body' | $sysutil";
    }
    @exec($command,$stat);
}

/* 把指定内容以指定文件名的附件发送 */
function sendTextAsAttachment($message,$subject,$addr,$fromuser='mailer',$content=null,$filename='attachment.txt',$sysuser='madreport',$sysutil="/usr/sbin/sendmail -t") {
    $preamble= "\n".
        "        This message is in MIME format.  But if you can see this,\n".
        "        you aren't using a MIME aware mail program.  Some parts of\n".
        "        of this message have been uuencoded for transport.  On a Unix\n".
        "        system, the program uudecode should be used to restore the file.\n\n";
    $body.="From: ".mailHeaderEncode($fromuser)." <$sysuser@localhost>\n";
    $body ="To: $addr\n";
    $body.="Subject: ".mailHeaderEncode($subject)."\n";
    $body.="X-Mailer: MadPHPSender1.0\n";
    $body.="MIME-version: 1.0\n";
    $body.="Content-Type: multipart/mixed;\n";
    $body.="    boundary=\"=== This is the boundary between parts of the message. ===--\"\n\n";
    $body.=$preamble;
    $body.="--=== This is the boundary between parts of the message. ===--\n";
    $body.="Content-Type: text/plain; charset=\"utf-8\"\n\n";
    $body.=$message."\n";
    if (!empty($content)) {
        $tmp_file='/tmp/madsendtxt.tmp';
        $fp=@fopen($tmp_file,"wb");
        fputs($fp,$body);
        fputs($fp,"--=== This is the boundary between parts of the message. ===--\n");
        fputs($fp,"Content-Type: text/plain; name=\"$filename\"\n");
        fputs($fp,"Content-Disposition: attachment; filename=\"$filename\"\n\n");
        fputs($fp,"$content");
        fputs($fp,"\n--=== This is the boundary between parts of the message. ===----");
        fclose($fp);

        $command="/bin/cat $tmp_file | $sysutil";
    } else {
        $command="echo '$body' | $sysutil";
    }
    @exec($command,$stat);
}
?>
