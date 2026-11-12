#### Sobre

Este guia ensina a criar mapas táticos no Blender e importá-los para a Godot. O projeto detecta automaticamente os blocos caminháveis do mapa. Siga as etapas para manter a estrutura esperada pelo jogo.

#### Requisitos

- [Blender](https://www.blender.org/)
- Conhecimentos básicos de Blender
- [Exportador Blender para Godot](https://github.com/godotengine/godot-blender-exporter)

#### Criar o mapa

Crie um novo projeto no Blender e remova todos os objetos: pressione `A` e depois `X`.
![Etapa 1](./img/1.png)

Adicione um cubo com `Shift+A` e selecione **Mesh > Cube**.
![Etapa 2](./img/2.png)

Confira se o tamanho do cubo é de 1 m.
![Etapa 3](./img/3.png)

No modo de edição (`Tab`), pressione `S` para ativar a escala. Clique para cancelar e ajuste o tamanho pelo menu.
![Etapa 4](./img/4.png)

Neste exemplo, o mapa terá uma grade simples de 5 x 5.
![Etapa 5](./img/5.png)

No menu superior, selecione **Seleção de faces (Face Select)**.
![Etapa 6](./img/6.png)

Mude para a vista inferior clicando no eixo `-Z`, no canto superior direito.
![Etapa 7](./img/7.png)

Selecione a face inferior e pressione `X` para removê-la.
![Etapa 8](./img/8.png)

Agora você terá uma malha aberta.
![Etapa 9](./img/9.png)

Crie a grade adicionando cortes com `Ctrl+R`.
![Etapa 10](./img/10.png)

Para criar um mapa 5 x 5, adicione quatro cortes em cada lado da malha para manter a proporção.
![Etapa 11](./img/11.png)

Agora você pode editar o mapa e adicionar texturas.
![Etapa 12](./img/12.png)

#### Criar os blocos

Use o eixo `Z`, no canto superior direito, para ir à vista superior.
![Etapa 13](./img/13.png)

Na vista superior, selecione todas as faces visíveis.
![Etapa 14](./img/14.png)

Essas faces formam a superfície e os blocos caminháveis pelos personagens.
![Etapa 15](./img/15.png)

Pressione `Shift+D` para duplicar. Você poderá mover a superfície da malha, mas não precisa movê-la neste passo; a imagem mostra apenas o resultado esperado.
![Etapa 16](./img/16.png)

Pressione `P` e escolha **Seleção (Selection)** para separar as faces caminháveis da malha.
![Etapa 17](./img/17.png)

Agora haverá dois objetos: `Cube` e `Cube.001`.
![Etapa 18](./img/18.png)

Renomeie-os para `Terrain` e `Tile`.
![Etapa 19](./img/19.png)

Oculte `Terrain` por enquanto.
![Etapa 20](./img/20.png)

Selecione `Tile` e entre no modo de edição.
![Etapa 21](./img/21.png)

No menu, use **Malha > Separar > Faces por arestas (Mesh > Split > Face by Edges)**.
![Etapa 22](./img/22.png)

Isso separa cada bloco dos demais.
![Etapa 23](./img/23.png)

Pressione `P` novamente e selecione **Por partes soltas (By Loose Parts)**.
![Etapa 24](./img/24.png)

Cada bloco agora será um objeto independente.
![Etapa 25](./img/25.png)

No modo de objeto, selecione todos os blocos e use **Objeto > Definir origem > Origem na geometria (Object > Set Origin > Origin to Geometry)**.
![Etapa 26](./img/26.png)

Cada bloco agora tem sua própria origem.
![Etapa 27](./img/27.png)

Com todos os blocos selecionados, pressione `Ctrl+A`, escolha **Escala (Scale)** e confirme. A aparência não muda, mas a escala de cada bloco é redefinida para 1 x 1, em vez de manter a escala da malha 5 x 5.
![Etapa 28](./img/28.png)

Confira os valores no painel lateral.
![Etapa 29](./img/29.png)

Abra o espaço de trabalho **Edição UV (UV Editing)**, selecione todos os blocos e pressione `U` para desembrulhar as UVs.
![Etapa 30](./img/30.png)

Confira se todos os blocos estão visíveis na janela à esquerda.
![Etapa 31](./img/31.png)

Selecione todos os blocos.
![Etapa 32](./img/32.png)

Use **UV > Reset** para redefinir as projeções UV.
![Etapa 33](./img/33.png)

Confira se cada bloco ocupa todo o espaço UV.
![Etapa 34](./img/34.png)

#### Exportar para a Godot

Torne `Terrain` visível novamente.
![Etapa 35](./img/35.png)

Exporte como `.escn`.
![Etapa 36](./img/36.png)

Salve a cena exportada na raiz do projeto.
![Etapa 37](./img/37.png)

Abra o arquivo no editor da Godot.
![Etapa 38](./img/38.png)

Duplique a cena-modelo `test_arena`.
![Etapa 39](./img/39.png)

Dê um novo nome à cópia.
![Etapa 40](./img/40.png)

Mova os blocos para o nó espacial `Tiles`. Recomenda-se remover primeiro os blocos antigos.
![Etapa 45](./img/45.png)
![Etapa 46](./img/46.png)
![Etapa 47](./img/47.png)

Copie e cole os blocos da cena exportada para a nova arena.
![Etapa 48](./img/48.png)
![Etapa 49](./img/49.png)

Faça o mesmo com a malha do terreno.
![Etapa 50](./img/50.png)
![Etapa 51](./img/51.png)
![Etapa 52](./img/52.png)
![Etapa 53](./img/53.png)

Desloque a malha do terreno um pouco para baixo.
![Etapa 54](./img/54.png)

Agora duplique a cena-modelo `test_level`.
![Etapa 56](./img/56.png)
![Etapa 57](./img/57.png)

Substitua o nó `Arena` pela arena que você configurou.
![Etapa 58](./img/58.png)
![Etapa 59](./img/59.png)
![Etapa 60](./img/60.png)

Adicione e posicione os personagens necessários.
![Etapa 61](./img/61.png)

Você já pode excluir o arquivo `.escn` exportado do projeto e fechar sua aba de visualização.
![Etapa 62](./img/62.png)
![Etapa 63](./img/63.png)

Teste sua nova fase.
![Etapa 64](./img/64.png)




















































