const express = require('express');
const app = express();
require('dotenvx').load();

app.get('/', (req, res) => {
  res.send('Welcome to Gyld!');
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Gyld server running on port ${PORT}`);
});
