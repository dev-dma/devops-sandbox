from flask import Flask, jsonify
import time, os

app = Flask(__name__)
START_TIME = time.time()

@app.route("/")
def home():
    return jsonify({
        "message": "Hello from DevOps Sandbox! 🚀",
        "env_id":   os.environ.get("ENV_ID",   "unknown"),
        "env_name": os.environ.get("ENV_NAME", "unknown"),
        "uptime":   f"{time.time() - START_TIME:.1f}s"
    })

@app.route("/health")
def health():
    return jsonify({"status": "ok", "timestamp": int(time.time())})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)
