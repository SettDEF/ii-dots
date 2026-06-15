#!/usr/bin/env python3
# Background daemon to receive notification payloads from the Windows VM and trigger native Linux desktop notifications.

import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class NotificationHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path == '/notify':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            try:
                data = json.loads(post_data.decode('utf-8'))
                title = data.get('title', 'Windows VM')
                message = data.get('message', '')
                urgency = data.get('urgency', 'normal') # low, normal, critical
                
                # Call notify-send on the host
                cmd = ['notify-send', '-a', 'Windows VM', '-u', urgency, title, message]
                subprocess.run(cmd, check=True)
                
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(b'{"status": "ok"}')
            except Exception as e:
                self.send_response(400)
                self.end_headers()
                self.wfile.write(f'{{"error": "{str(e)}"}}'.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    # Disable default request logging to avoid cluttering stdout
    def log_message(self, format, *args):
        return

def run(server_class=HTTPServer, handler_class=NotificationHandler, port=9999):
    # Listen on all interfaces so the VM can reach it via the virtual network bridge (gateway IP)
    server_address = ('0.0.0.0', port)
    httpd = server_class(server_address, handler_class)
    print(f'Starting notification daemon on port {port}...')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == '__main__':
    run()
