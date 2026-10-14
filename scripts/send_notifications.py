"""Explicit, opt-in SMTP delivery. Dry-run by default; never called by web requests."""
import argparse
from email.message import EmailMessage
import os
from pathlib import Path
import smtplib
import ssl
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.db import connection

def deliver(smtp,row,sender):
    message=EmailMessage();message['From']=sender;message['To']=row[1];message['Subject']='AeroFlow DEMO — '+row[2]
    message['Message-ID']=f'<aeroflow-notification-{row[0]}@aeroflow.local>'
    message.set_content(row[3]+'\n\nThông báo từ hệ thống mô phỏng AeroFlow, không phải hãng hàng không thực tế.')
    smtp.send_message(message)

def run(send=False,limit=20):
    with connection() as conn:
        # Serialize the worker without holding the inventory lock while connecting to SMTP.
        result=conn.execute("DECLARE @r int;EXEC @r=sys.sp_getapplock @Resource='AeroFlow:email',@LockMode='Exclusive',@LockOwner='Session',@LockTimeout=1000;SELECT @r;").fetchone()[0]
        if result<0: raise RuntimeError('Another email worker is running.')
        rows=conn.execute('SELECT TOP(?) n.NotificationID,u.Email,n.Title,n.Message FROM dbo.Notifications n JOIN dbo.Users u ON u.UserID=n.UserID JOIN dbo.UserPreferences p ON p.UserID=n.UserID LEFT JOIN dbo.NotificationDeliveries d ON d.NotificationID=n.NotificationID WHERE u.IsActive=1 AND p.EmailNotifications=1 AND d.SentAt IS NULL AND COALESCE(d.Attempts,0)<5 ORDER BY n.NotificationID',limit).fetchall()
        if not send: print('Eligible notifications:',len(rows),'(dry run; no email sent)');return
        host=os.getenv('SMTP_HOST','');sender=os.getenv('SMTP_FROM','')
        if not host or not sender: raise ValueError('Set SMTP_HOST and SMTP_FROM before --send.')
        # Always use TLS; no plaintext SMTP mode.
        with smtplib.SMTP(host,int(os.getenv('SMTP_PORT','587')),timeout=15) as smtp:
            smtp.ehlo();smtp.starttls(context=ssl.create_default_context());smtp.ehlo()
            if os.getenv('SMTP_USERNAME'): smtp.login(os.environ['SMTP_USERNAME'],os.environ.get('SMTP_PASSWORD',''))
            for row in rows:
                if not conn.execute('SELECT 1 FROM dbo.NotificationDeliveries WHERE NotificationID=?',row[0]).fetchone(): conn.execute('INSERT dbo.NotificationDeliveries(NotificationID) VALUES(?)',row[0])
                conn.execute('UPDATE dbo.NotificationDeliveries SET Attempts=Attempts+1 WHERE NotificationID=?',row[0]);conn.commit()
                try:
                    deliver(smtp,row,sender)
                    conn.execute('UPDATE dbo.NotificationDeliveries SET SentAt=SYSUTCDATETIME(),LastError=NULL WHERE NotificationID=?',row[0])
                except (smtplib.SMTPException,OSError) as error:
                    conn.execute('UPDATE dbo.NotificationDeliveries SET LastError=? WHERE NotificationID=?',type(error).__name__,row[0])
                conn.commit()
        print('Processed notifications:',len(rows))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--send',action='store_true');p.add_argument('--limit',type=int,default=20);a=p.parse_args()
    if not 1<=a.limit<=100: p.error('Limit must be 1..100')
    run(a.send,a.limit)
