import { useContext, Signal } from "solid-js"; 
import { A, useNavigate } from "@solidjs/router";
import { Store } from "solid-js/store";
import DropDownMenu from "../components/DropDownMenu.tsx";
import { getToken } from "../utils/token";
import { apiDomain, AuthContext, MusicPlayerStateContext } from "../index.tsx"; 

const HomePage = () => {
    document.title = "Blue waves";

    const [token, setToken] = useContext(AuthContext) as Signal<string>;

    const [musicPlayerState] = useContext(MusicPlayerStateContext) as Store<any>;

    const navigate = useNavigate();

    const logout = async () => {
        // Fetch new token if user refreshed the page
        if (token() === "") setToken(await getToken());

        // Logout user
        const response = await fetch(`${apiDomain}/api/v1/users/logout`, {
            method: "POST",
            headers: { "Authorization": `Bearer ${token()}` },
            credentials: "include"
        });

        if (response.ok) {
            setToken("");
            navigate("/login");
        } else if (response.status === 401) {
            setToken(await getToken());
            await logout();
        }
    }

    return (
        <div class="flex flex-row-reverse">
            <div class={`flex flex-col w-1/5 ${musicPlayerState.showMusicPlayer ? "h-[calc(100vh-5rem)]" : "h-screen"} border-r-2 fixed left-0`}>
                <nav class="flex flex-col items-center p-6">
                    <A href="/home" class="text-2xl font-medium m-6">Home</A>
                    <A href="/library" class="text-2xl font-medium m-6">Library</A>
                    <A href="/playlists" class="text-2xl font-medium m-6">Playlists</A>
                </nav>
            </div>
            <div class="flex flex-col w-4/5 mb-20">
                <div class="flex justify-end">
                    <div class="m-5">
                        <DropDownMenu onSelect={logout}>
                        </DropDownMenu>
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
