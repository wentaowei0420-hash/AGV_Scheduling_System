from ui_windows.backend_api_unified import app


if __name__ == '__main__':
    print('Unified backend starter running at http://127.0.0.1:5000')
    app.run(host='0.0.0.0', port=5000, debug=False)
