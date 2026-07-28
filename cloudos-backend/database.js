const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, 'cloudos.db');
const rawDb = new sqlite3.Database(dbPath);

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
            wallpaper TEXT DEFAULT 'https://images.unsplash.com/photo-1579546929518-9e396f3cc809?q=80&w=2070',
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
        CREATE TABLE IF NOT EXISTS system_events (
            id TEXT PRIMARY KEY,
            user_id TEXT,
            event_type TEXT NOT NULL,
            details TEXT,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
    `);
});

const db = {
    rawDb,
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
