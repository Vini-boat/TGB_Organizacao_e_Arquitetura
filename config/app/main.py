import socket

import psycopg2
from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

HOST = socket.gethostname()
BANCO = "host=10.10.10.10 port=5000 dbname=placar user=app password=app connect_timeout=2"
NOMES = {"10.10.10.31": "db1", "10.10.10.32": "db2"}

app = FastAPI()
templates = Jinja2Templates(directory="templates")


def sql(comando, args=()):
    # Uma conexão nova por comando: depois de um failover, a próxima já vai para o primário novo.
    con = psycopg2.connect(BANCO)
    try:
        with con, con.cursor() as cur:
            cur.execute(comando, args)
            return cur.fetchall() if cur.description else []
    finally:
        con.close()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/", response_class=HTMLResponse)
def index(request: Request):
    return templates.TemplateResponse(request, "index.html", {"hostname": HOST})


@app.post("/clique")
def clique(response: Response):
    try:
        sql("INSERT INTO cliques (app, banco) VALUES (%s, host(inet_server_addr()))", (HOST,))
    except psycopg2.Error:
        response.status_code = 503
    return {"app": HOST}


@app.get("/api/estado")
def estado(response: Response):
    try:
        banco, total = sql("SELECT host(inet_server_addr()), count(*) FROM cliques")[0]
        ultimos = sql("SELECT to_char(quando AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI:SS'), app, banco"
                      " FROM cliques ORDER BY id DESC LIMIT 10")
    except psycopg2.Error:
        response.status_code = 503
        return {"app": HOST}
    return {
        "app": HOST,
        "banco": NOMES.get(banco, banco),
        "total": total,
        "ultimos": [[hora, a, NOMES.get(b, b)] for hora, a, b in ultimos],
    }
