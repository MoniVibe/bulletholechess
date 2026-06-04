function sendJson(socket, payload) {
  socket.send(JSON.stringify(payload));
}

module.exports = {
  sendJson,
};
