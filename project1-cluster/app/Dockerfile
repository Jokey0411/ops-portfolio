FROM python:3.11-alpine

# PyMySQL 是纯 Python 库，无需编译，alpine 上直接装
RUN pip install --no-cache-dir pymysql -i https://mirrors.cloud.tencent.com/pypi/simple \
    && rm -rf /root/.cache/pip

WORKDIR /app
COPY app.py /app/app.py

EXPOSE 8080

CMD ["python", "-u", "app.py"]
