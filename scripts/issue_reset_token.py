"""Local operator recovery for demo accounts. Tokens never appear in HTTP responses/logs."""
import argparse
import hashlib
import secrets
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app.db import connection

def issue(email):
    token=secrets.token_urlsafe(36)
    with connection() as conn:
        row=conn.execute('SELECT UserID FROM dbo.Users WITH(UPDLOCK,HOLDLOCK) WHERE Email=? AND IsActive=1',email.strip().lower()).fetchone()
        if not row: raise ValueError('No active account found.')
        conn.execute('UPDATE dbo.PasswordResetTokens SET UsedAt=SYSUTCDATETIME() WHERE UserID=? AND UsedAt IS NULL',row[0])
        conn.execute('INSERT dbo.PasswordResetTokens(TokenHash,UserID,ExpiresAt) VALUES(?,?,DATEADD(minute,15,SYSUTCDATETIME()))',hashlib.sha256(token.encode()).hexdigest(),row[0])
        conn.execute("INSERT dbo.AuditLogs(Entity,EntityID,Action) VALUES('Users',?,'RESET_TOKEN_ISSUED')",row[0])
    return token

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--email',required=True);args=parser.parse_args()
    print('Verify the account owner before giving them this single-use, 15-minute token:')
    print(issue(args.email))
