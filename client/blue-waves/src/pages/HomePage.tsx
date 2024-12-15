import { A, useNavigate, createAsync } from "@solidjs/router";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "../components/ui/dropdown-menu";
import { getToken } from "../utils/token";
import { api } from "../index.tsx";

const HomePage = () => {

    const token = createAsync(() => getToken());

    const navigate = useNavigate();

    const logout = async () => {
        // Logout user
        await api.post("users/logout", {
            headers: {
                "Authorization": `Bearer ${token()}`
            },
            credentials: "include"
        });

        // Navigate to login page
        navigate("/login");
    }

    return (
        <div class="flex">
            <div class="flex flex-col w-1/5 h-screen border-2">
                <nav class="flex flex-col items-center p-6">
                    <A href="/library" class="text-2xl font-medium m-6">Library</A>
                    <A href="/playlists" class="text-2xl font-medium m-6">Playlists</A>
                </nav>
            </div>
            <div class="flex flex-col w-4/5">
                <div class="flex justify-end">
                    <div class="m-5 border-2">
                        <DropdownMenu>
                            <DropdownMenuTrigger>Open</DropdownMenuTrigger>
                            <DropdownMenuContent>
                                <DropdownMenuItem onSelect={logout}>Logout</DropdownMenuItem>
                            </DropdownMenuContent>
                        </DropdownMenu>
                    </div>
                </div>
                <div class="flex justify-between h-20 p-6">
                    <h1 class="text-2xl font-medium">Recently Played</h1>
                    <A href="/recently-played" class="text-2xl">See All</A>
                </div>
            </div>
        </div>
    )
}

export default HomePage;
