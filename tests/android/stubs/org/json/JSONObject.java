package org.json;

import java.util.LinkedHashMap;
import java.util.Map;

/** Test stand-in: only what AgentStatus uses, and a small parser for the helper's replies. */
public class JSONObject {
    private final Map<String, Object> map = new LinkedHashMap<>();

    public JSONObject() {}

    public JSONObject(String s) throws JSONException {
        Parser p = new Parser(s);
        Object v = p.value();
        if (!(v instanceof JSONObject o)) throw new JSONException("not an object");
        map.putAll(o.map);
    }

    public JSONObject put(String k, Object v) {
        map.put(k, v);
        return this;
    }

    public String getString(String k) throws JSONException {
        if (map.get(k) instanceof String s) return s;
        throw new JSONException("no " + k);
    }

    public JSONObject getJSONObject(String k) throws JSONException {
        if (map.get(k) instanceof JSONObject o) return o;
        throw new JSONException("no " + k);
    }

    public String optString(String k) {
        return optString(k, "");
    }

    public String optString(String k, String fallback) {
        Object v = map.get(k);
        return v == null ? fallback : v.toString();
    }

    public long optLong(String k, long fallback) {
        return map.get(k) instanceof Number n ? n.longValue() : fallback;
    }

    public JSONArray optJSONArray(String k) {
        return map.get(k) instanceof JSONArray a ? a : null;
    }

    @Override
    public String toString() {
        StringBuilder b = new StringBuilder("{");
        for (Map.Entry<String, Object> e : map.entrySet()) {
            if (b.length() > 1) b.append(',');
            b.append(quote(e.getKey())).append(':');
            Object v = e.getValue();
            b.append(v instanceof String s ? quote(s) : String.valueOf(v));
        }
        return b.append('}').toString();
    }

    private static String quote(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    private static final class Parser {
        private final String s;
        private int i;

        Parser(String s) {
            this.s = s;
        }

        Object value() throws JSONException {
            skip();
            if (i >= s.length()) throw new JSONException("end");
            char c = s.charAt(i);
            if (c == '{') {
                JSONObject o = new JSONObject();
                i++;
                skip();
                if (s.charAt(i) == '}') {
                    i++;
                    return o;
                }
                while (true) {
                    skip();
                    String k = (String) value();
                    skip();
                    expect(':');
                    o.map.put(k, value());
                    skip();
                    if (s.charAt(i++) == '}') return o;
                }
            }
            if (c == '[') {
                JSONArray a = new JSONArray();
                i++;
                skip();
                if (s.charAt(i) == ']') {
                    i++;
                    return a;
                }
                while (true) {
                    a.list.add(value());
                    skip();
                    if (s.charAt(i++) == ']') return a;
                }
            }
            if (c == '"') {
                StringBuilder b = new StringBuilder();
                i++;
                while (s.charAt(i) != '"') {
                    char d = s.charAt(i++);
                    if (d == '\\') {
                        char e = s.charAt(i++);
                        if (e == 'u') {
                            b.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
                            i += 4;
                        } else {
                            b.append(e == 'n' ? '\n' : e == 't' ? '\t' : e);
                        }
                    } else {
                        b.append(d);
                    }
                }
                i++;
                return b.toString();
            }
            int start = i;
            while (i < s.length() && ",}] \n\r\t".indexOf(s.charAt(i)) < 0) i++;
            String t = s.substring(start, i);
            if (t.equals("true") || t.equals("false")) return Boolean.valueOf(t);
            if (t.equals("null")) return null;
            try {
                return t.contains(".") || t.contains("e") ? (Object) Double.valueOf(t) : (Object) Long.valueOf(t);
            } catch (NumberFormatException e) {
                throw new JSONException("bad value " + t);
            }
        }

        private void skip() {
            while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++;
        }

        private void expect(char c) throws JSONException {
            if (s.charAt(i++) != c) throw new JSONException("expected " + c);
        }
    }
}
