-- The template's one table, as its init.sql creates it.
--
-- Upstream loaded init.sql into the database by hand (a provider's SQL editor,
-- or psql) before deploying. Here it is a migration, applied by db-migrate to
-- each environment's Supabase project before the Worker deploys.
CREATE TABLE IF NOT EXISTS books (
    id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    author VARCHAR(255) NOT NULL,
    description TEXT,
    image_url VARCHAR(255),
    genre VARCHAR(50) DEFAULT 'Unknown',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
