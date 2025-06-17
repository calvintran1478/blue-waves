import { query, redirect } from "@solidjs/router";

export const getToken = query(async () => {
    const response = await fetch("http://localhost:8080/api/v1/users/token", {
        credentials: "include"
    });

    if (response.ok) {
        return await response.text();
    } else {
        throw redirect("/login");
    }
}, "token");
