import os
import re
import mimetypes
from http.server import HTTPServer, BaseHTTPRequestHandler

class RangeHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_HEAD(self):
        self.send_resp_custom(head_only=True)

    def do_GET(self):
        self.send_resp_custom(head_only=False)

    def send_resp_custom(self, head_only=False):
        path = self.path.split('?')[0].lstrip('/')
        if not path or path == '/':
            path = 'index.html'
        
        file_path = os.path.join('/home/user/sweeda-real-estate-office-elc/marketing', path)
        if not os.path.exists(file_path) or os.path.isdir(file_path):
            self.send_error(404, "File Not Found")
            return

        file_size = os.path.getsize(file_path)
        mime_type, _ = mimetypes.guess_type(file_path)
        if not mime_type:
            mime_type = 'application/octet-stream'

        range_header = self.headers.get('Range', None)

        if range_header:
            match = re.match(r'bytes=(\d+)-(\d*)', range_header)
            if match:
                start = int(match.group(1))
                end = int(match.group(2)) if match.group(2) else file_size - 1
                if start >= file_size or end >= file_size or start > end:
                    self.send_error(416, "Requested Range Not Satisfiable")
                    return

                length = end - start + 1
                self.send_response(206)
                self.send_header('Content-Type', mime_type)
                self.send_header('Content-Range', f'bytes {start}-{end}/{file_size}')
                self.send_header('Content-Length', str(length))
                self.send_header('Accept-Ranges', 'bytes')
                self.send_header('Access-Control-Allow-Origin', '*')
                self.end_headers()

                if not head_only:
                    with open(file_path, 'rb') as f:
                        f.seek(start)
                        bytes_left = length
                        while bytes_left > 0:
                            chunk_size = min(65536, bytes_left)
                            chunk = f.read(chunk_size)
                            if not chunk:
                                break
                            self.wfile.write(chunk)
                            bytes_left -= len(chunk)
                return

        self.send_response(200)
        self.send_header('Content-Type', mime_type)
        self.send_header('Content-Length', str(file_size))
        self.send_header('Accept-Ranges', 'bytes')
        self.send_header('Access-Control-Allow-Origin', '*')
        if file_path.endswith('.zip') or 'download=1' in self.path:
            self.send_header('Content-Disposition', f'attachment; filename="{os.path.basename(file_path)}"')
        self.end_headers()

        if not head_only:
            with open(file_path, 'rb') as f:
                bytes_left = file_size
                while bytes_left > 0:
                    chunk_size = min(65536, bytes_left)
                    chunk = f.read(chunk_size)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    bytes_left -= len(chunk)

    def log_message(self, format, *args):
        pass

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), RangeHTTPRequestHandler)
    print("Serving on 0.0.0.0:8080...")
    server.serve_forever()
