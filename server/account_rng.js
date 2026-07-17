'use strict';

const { randomBytes } = require('crypto');

const EVENT_NAME = 'mz_bank:internal:accountRandomBytes';
const REQUIRED_BYTES = 4;

// Evento exclusivamente server-side. Ele não é registrado como evento de rede,
// não aceita dados do client e não expõe export público.
on(EVENT_NAME, (size, callback) => {
    if (typeof callback !== 'function') return;
    if (size !== REQUIRED_BYTES) {
        callback(null, 'invalid_random_size');
        return;
    }

    try {
        callback(randomBytes(REQUIRED_BYTES).toString('hex').toUpperCase(), null);
    } catch (_error) {
        callback(null, 'node_crypto_unavailable');
    }
});
