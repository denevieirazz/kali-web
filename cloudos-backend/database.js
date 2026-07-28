const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, 'cloudos.db');
const rawDb = new sqlite3.Database(dbPath);

console.log('🛡️ Inicializando Banco de Dados CloudOS (SQLite)...');

rawDb.serialize(() => {
    rawDb.run("PRAGMA journal_mode = WAL");
    rawDb.run("PRAGMA foreign_keys = ON");

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            tier TEXT DEFAULT 'free',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS user_settings (
            user_id TEXT PRIMARY KEY,
            theme TEXT DEFAULT 'dark',
            wallpaper TEXT DEFAULT 'linear-gradient(135deg, #0f0c29, #302b63, #24243e)',
            language TEXT DEFAULT 'pt-BR',
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS desktop_state (
            user_id TEXT PRIMARY KEY,
            icon_positions TEXT DEFAULT '{}',
            open_windows TEXT DEFAULT '[]',
            taskbar_pins TEXT DEFAULT '[]',
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS workspaces (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            state TEXT DEFAULT '{}',
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS snapshots (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS system_events (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            event_type TEXT NOT NULL,
            details TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS file_metadata (
            user_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            is_favorite INTEGER DEFAULT 0,
            tags TEXT DEFAULT '[]',
            last_opened DATETIME,
            PRIMARY KEY (user_id, file_path)
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS installed_apps (
            user_id TEXT NOT NULL,
            app_id TEXT NOT NULL,
            is_pinned INTEGER DEFAULT 0,
            PRIMARY KEY (user_id, app_id)
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS notifications (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            title TEXT NOT NULL,
            message TEXT,
            type TEXT DEFAULT 'info',
            is_read INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS kali_tool_favorites (
            user_id TEXT NOT NULL,
            tool_id TEXT NOT NULL,
            PRIMARY KEY (user_id, tool_id)
        );
    `);

    rawDb.run(`
        CREATE TABLE IF NOT EXISTS kali_tool_recent (
            user_id TEXT NOT NULL,
            tool_id TEXT NOT NULL,
            opened_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (user_id, tool_id)
        );
    `);
});

const db = {
    rawDb,
    exec(sql) {
        return new Promise((resolve, reject) => {
            rawDb.exec(sql, (err) => {
                if (err) reject(err);
                else resolve();
            });
        });
    },
    prepare(sql) {
        return {
            async get(...params) {
                return new Promise((resolve, reject) => {
                    rawDb.get(sql, params, (err, row) => {
                        if (err) reject(err);
                        else resolve(row);
                    });
                });
            },
            async all(...params) {
                return new Promise((resolve, reject) => {
                    rawDb.all(sql, params, (err, rows) => {
                        if (err) reject(err);
                        else resolve(rows);
                    });
                });
            },
            async run(...params) {
                return new Promise((resolve, reject) => {
                    rawDb.run(sql, params, function (err) {
                        if (err) reject(err);
                        else resolve({ lastID: this.lastID, changes: this.changes });
                    });
                });
            }
        };
    }
};

module.exports = db;
