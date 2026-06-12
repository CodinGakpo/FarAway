from app.auth import verify_firebase_token
import sys

token = sys.argv[1]
try:
    claims = verify_firebase_token(token)
    print("SUCCESS", claims)
except Exception as e:
    print("FAILED", type(e), str(e))
