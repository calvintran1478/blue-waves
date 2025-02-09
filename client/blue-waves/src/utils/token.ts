import { query, redirect } from "@solidjs/router";
import { api } from "../index.tsx";

export const getToken = query(async () => {
    try {
        return await api.get("users/token", { credentials: "include" }).text();
    } catch (error) {
        throw redirect("/login");
    }
}, "token");
