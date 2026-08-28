from Crypto.Cipher import AES
from Crypto.Util.Padding import pad, unpad
import base64
from src.config import settings

class EncryptionService:
    
    def __init__(self):
        self.key = settings.AES_SECRET_KEY.encode('utf-8')[:32]
        self.block_size = AES.block_size

    def encrypt(self, data: str) -> str:
        cipher = AES.new(self.key, AES.MODE_CBC)
        ct_bytes = cipher.encrypt(pad(data.encode('utf-8'), self.block_size))
        iv = base64.b64encode(cipher.iv).decode('utf-8')
        ct = base64.b64encode(ct_bytes).decode('utf-8')
        return f'{iv}:{ct}'

    def decrypt(self, encrypted_data: str) -> str:
        iv, ct = encrypted_data.split(':')
        iv = base64.b64decode(iv)
        ct = base64.b64decode(ct)
        cipher = AES.new(self.key, AES.MODE_CBC, iv)
        pt = unpad(cipher.decrypt(ct), self.block_size)
        return pt.decode('utf-8')

encryption_service = EncryptionService()
