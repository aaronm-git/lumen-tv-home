package org.json;

import java.util.ArrayList;
import java.util.List;

public class JSONArray {
    final List<Object> list = new ArrayList<>();

    public int length() {
        return list.size();
    }

    public JSONObject getJSONObject(int i) throws JSONException {
        if (list.get(i) instanceof JSONObject o) return o;
        throw new JSONException("not an object");
    }
}
