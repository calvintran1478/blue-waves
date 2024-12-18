import { lazy } from "solid-js";
import { render } from "solid-js/web";
import { Router } from "@solidjs/router";
import { QueryClient, QueryClientProvider } from '@tanstack/solid-query'; 
import ky from "ky";
import "./index.css"

const RegisterPage = lazy(() => import("./pages/RegisterPage"));
const LoginPage = lazy(() => import("./pages/LoginPage"));
const HomePage = lazy(() => import("./pages/HomePage"));
const LibraryPage = lazy(() => import("./pages/LibraryPage"));
const MusicPage = lazy(() => import("./pages/MusicPage"));

const routes = [
    {
        path: "/register",
        component: RegisterPage,
    },
    {
        path: "/login",
        component: LoginPage
    },
    {
        path: "/home",
        component: HomePage
    },
    {
        path: "/library",
        component: LibraryPage
    },
    {
        path: "/library/:music_id",
        component: MusicPage
    }
]

const queryClient = new QueryClient({
    defaultOptions: {
        queries: {
            enabled: false,
            retry: false
        }
    }
});

export const api = ky.create({
    prefixUrl: "http://localhost:8080/api/v1",
    hooks: {
        beforeError: [
            async(error) => {
                // Parse error message from response body
                error.message = (await error.response.json() as { error: string }).error;
                return error;
            }
        ]
    }
});

render(
    () => (
        <QueryClientProvider client={queryClient}>
            <Router>{routes}</Router>
        </QueryClientProvider>
    ),
    document.getElementById("root")!
);
