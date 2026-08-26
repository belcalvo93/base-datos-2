-- ============================================================
-- Trabajo Práctico N.º 1 — Base de Datos 2
-- ============================================================
-- Elimina tablas y tipos previos si ya existen para permitir reejecuciones
DROP TABLE IF EXISTS detalle_pedido CASCADE;
DROP TABLE IF EXISTS pedido CASCADE;
DROP TABLE IF EXISTS producto CASCADE;
DROP TABLE IF EXISTS categoria CASCADE;
DROP TABLE IF EXISTS cliente CASCADE;
DROP TYPE IF EXISTS forma_pago_enum CASCADE;
-- ------------------------------------------------------------
-- Tipos enumerados
-- ------------------------------------------------------------
-- forma_pago es un dominio cerrado (EFECTIVO / TARJETA / TRANSFERENCIA),
CREATE TYPE forma_pago_enum AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');

-- ------------------------------------------------------------
-- CATEGORIA
-- Participación parcial respecto a PRODUCTO (R1): puede existir
-- una categoría sin productos todavía (p. ej. recién creada).
-- ------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(80)     NOT NULL UNIQUE,
    activo          BOOLEAN         NOT NULL DEFAULT TRUE, -- R7: baja lógica, nunca borrado físico
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- CLIENTE
-- nombre y apellido separados (Parte 1: se usan de forma
-- independiente para ordenar/buscar). email es clave candidata (R6).
-- ------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(80)     NOT NULL,
    apellido        VARCHAR(80)     NOT NULL,
    email           VARCHAR(150)    NOT NULL UNIQUE, -- clave candidata (R6)
    telefono        VARCHAR(30),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- PRODUCTO
-- Participación total respecto a CATEGORIA (R1): todo producto
-- pertenece exactamente a una categoría -> id_categoria NOT NULL.
-- ------------------------------------------------------------
CREATE TABLE producto (
    id_producto     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          VARCHAR(120)    NOT NULL,
    descripcion     TEXT,
    precio          NUMERIC(10,2)   NOT NULL CHECK (precio >= 0), -- R5
    stock           INTEGER         NOT NULL DEFAULT 0 CHECK (stock >= 0), -- R5
    activo          BOOLEAN         NOT NULL DEFAULT TRUE, -- R7: baja lógica
    id_categoria    BIGINT          NOT NULL
                        REFERENCES categoria (id_categoria)
                        ON DELETE RESTRICT, -- una categoría con productos no puede borrarse; se da de baja lógicamente (R7)
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------
-- PEDIDO
-- Participación total respecto a CLIENTE (R2): todo pedido
-- pertenece exactamente a un cliente registrado -> id_cliente NOT NULL.
-- ------------------------------------------------------------
CREATE TABLE pedido (
    id_pedido       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha           TIMESTAMPTZ     NOT NULL DEFAULT now(),
    forma_pago      forma_pago_enum NOT NULL,
    id_cliente      BIGINT          NOT NULL
                        REFERENCES cliente (id_cliente)
                        ON DELETE RESTRICT -- protege el historial de pedidos; no se borra un cliente con pedidos asociados
);

-- ------------------------------------------------------------
-- DETALLE_PEDIDO (tabla intermedia N:M entre PEDIDO y PRODUCTO)
-- Clave sustituta propia (id_detalle) + UNIQUE(id_pedido, id_producto)
-- para no duplicar un mismo producto en un mismo pedido (justificado
-- en la Parte 2). precio_unitario congela el precio histórico (R4),
-- independiente del precio de lista vigente en producto.
-- subtotal NO se almacena: se recalcula (cantidad * precio_unitario)
-- según lo resuelto en la Parte 3 (evita la dependencia transitiva
-- que rompía 3FN).
-- ------------------------------------------------------------
CREATE TABLE detalle_pedido (
    id_detalle      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cantidad        INTEGER         NOT NULL CHECK (cantidad > 0),
    precio_unitario NUMERIC(10,2)   NOT NULL CHECK (precio_unitario >= 0), -- R5
    id_pedido       BIGINT          NOT NULL
                        REFERENCES pedido (id_pedido)
                        ON DELETE CASCADE, -- una línea de detalle no tiene sentido sin su pedido: si el pedido se elimina, sus líneas se eliminan con él
    id_producto     BIGINT          NOT NULL
                        REFERENCES producto (id_producto)
                        ON DELETE RESTRICT, -- protege el historial de ventas: no se borra un producto referenciado en detalles (R7: se da de baja lógicamente)
    UNIQUE (id_pedido, id_producto) -- dentro de un mismo pedido, un producto no se repite en más de una línea
);

-- ------------------------------------------------------------
-- Índices
-- ------------------------------------------------------------

-- Acelera "traer todos los pedidos de un cliente" (consulta muy
-- frecuente en el sistema: historial de compras de un cliente).
CREATE INDEX idx_pedido_id_cliente ON pedido (id_cliente);

-- Acelera "listar los productos vigentes (activos) de una categoría",
-- filtrando directamente por categoría + estado activo.
CREATE INDEX idx_producto_categoria_activo ON producto (id_categoria) WHERE activo = TRUE;

-- Acelera "reconstruir el detalle de un pedido" y "ver en qué pedidos
-- apareció un producto" (join frecuente entre detalle_pedido y ambas puntas).
CREATE INDEX idx_detalle_pedido_id_producto ON detalle_pedido (id_producto);