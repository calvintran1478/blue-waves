import { query, redirect } from "@solidjs/router";
import { api } from "../index.tsx";

export const getToken = query(async () => {
    try {
        const tokenResponse = await api.get("users/token", { credentials: "include" }).json<{"access_token": string}>();
        return tokenResponse["access_token"];
    } catch (error) {
        throw redirect("/login");
    }
}, "token");
