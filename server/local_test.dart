class Foo {
  void newInt() {
    var theAnswer = 445;

    another();
    another();

    print("The answer $theAnswer");
    throw "Well, that was wrong";
  }

  void another() {
    var theAnswer = 42;
    print("Another answer is $theAnswer");

  }

}

main() {
  print ("Startup");
  var f = new Foo();
  f.newInt();
}
