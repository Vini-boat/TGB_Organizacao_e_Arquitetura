-- Banco do placar. Rodar uma vez, no primário:
-- incus exec db1 -- su postgres -c "psql -f /srv/db/placar.sql"
CREATE USER app PASSWORD 'app';
CREATE DATABASE placar OWNER app;
\c placar
CREATE TABLE cliques (
    id     serial PRIMARY KEY,
    quando timestamptz DEFAULT now(),
    app    text,
    banco  text
);
ALTER TABLE cliques OWNER TO app;
