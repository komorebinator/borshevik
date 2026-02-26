import Soup from "gi://Soup?version=3.0";
import GLib from "gi://GLib";

export async function fetchJson(url, timeoutMs = 15000) {
  const session = new Soup.Session({
    timeout: Math.ceil(timeoutMs / 1000),
    user_agent: "borshevik-app-installer/1.0",
  });

  const message = Soup.Message.new("GET", url);

  const bytes = await new Promise((resolve, reject) => {
    session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, null, (_sess, res) => {
      try {
        const b = session.send_and_read_finish(res);
        const status = message.get_status();
        if (status < 200 || status >= 300) return reject(new Error(`HTTP ${status}`));
        resolve(b);
      } catch (e) {
        reject(e);
      }
    });
  });

  const text = new TextDecoder("utf-8").decode(bytes.get_data());
  return JSON.parse(text);
}

export async function fetchBytes(url, timeoutMs = 15000) {
  const session = new Soup.Session({
    timeout: Math.ceil(timeoutMs / 1000),
    user_agent: "borshevik-app-installer/1.0",
  });

  const message = Soup.Message.new("GET", url);

  const bytes = await new Promise((resolve, reject) => {
    session.send_and_read_async(message, GLib.PRIORITY_DEFAULT, null, (_sess, res) => {
      try {
        const b = session.send_and_read_finish(res);
        const status = message.get_status();
        if (status < 200 || status >= 300) return reject(new Error(`HTTP ${status}`));
        resolve(b);
      } catch (e) {
        reject(e);
      }
    });
  });

  return bytes;
}
