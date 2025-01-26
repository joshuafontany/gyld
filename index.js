// index.js
require('@dotenvx/dotenvx').config()
// or import('@dotenvx/dotenvx/config') if you're using esm

console.log(`Hello ${process.env.HELLO}`)